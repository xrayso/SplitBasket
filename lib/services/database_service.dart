import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:split_basket/services/notification_service.dart';
import 'package:uuid/uuid.dart';
import '../models/aggregated_resolution_request.dart';
import '../models/user.dart' as user_dart;
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../models/charges.dart';
import '../models/aggregated_charge.dart';
import 'split_math.dart';

/// Shown in place of someone who deleted their account. Usernames can't
/// contain spaces, so no real user can be called this.
const kDeletedUserName = 'Deleted user';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // User names rarely change, so look each one up once per app session.
  static final Map<String, Future<String>> _nameCache = {};

  /// Forgets cached names, e.g. on sign-out, so the next person to sign in
  /// sees current ones (including accounts deleted since).
  static void forgetNames() => _nameCache.clear();

  /// Reads a basket's items, lets [mutate] change them, and writes them back
  /// in one transaction. Items live in a single array on the basket, so a plain
  /// read-then-write would let two people's changes overwrite each other.
  Future<void> _mutateItems(
    String basketId,
    void Function(List<Map<String, dynamic>> items) mutate,
  ) {
    final basketRef = _db.collection('baskets').doc(basketId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(basketRef);
      if (!snap.exists) return;
      final items = List<Map<String, dynamic>>.from(
        (snap.data()?['items'] ?? const []).map((i) => Map<String, dynamic>.from(i)),
      );
      mutate(items);
      tx.update(basketRef, {'items': items});
    });
  }

  /// Starts a basket hosted by [hostId], who is its only member.
  Future<Basket> createBasket(String name, String hostId) async {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    final basket = Basket(
      id: Uuid().v4(),
      name: name,
      hostId: hostId,
      memberIds: [hostId],
      memberTokens: [],
      invitationCode: String.fromCharCodes(Iterable.generate(
          6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length)))),
    );
    await setBasket(basket);
    return basket;
  }

  // Create or update a basket
  Future<void> setBasket(Basket basket) {
    var options = SetOptions(merge: true);
    return _db.collection('baskets').doc(basket.id).set(basket.toMap(), options);
  }

  Future<Basket> getBasketById(String id) async{
    try {
      DocumentSnapshot doc = await _db.collection('baskets').doc(id).get();
      if (doc.exists) {
        return Basket.fromMap(doc.data() as Map<String, dynamic>);
      } else {
        throw Exception('Basket not found');
      }
    } catch (e) {
      rethrow;
    }
  }
  // Get a basket stream by ID
  Stream<Basket> streamBasket(String id) {
    return _db.collection('baskets').doc(id).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        throw Exception('Basket with ID $id does not exist.');
      }
      final data = snapshot.data();
      if (data == null) {
        throw Exception('Basket data is null for ID $id.');
      }
      try {
        return Basket.fromMap(data);
      } catch (e) {
        throw Exception('Error converting basket data: $e');
      }
    });
  }

  Future<void> setUser(user_dart.User user) {
    _nameCache.remove(user.id);
    var options = SetOptions(merge: true);
    return _db.collection('users').doc(user.id).set(user.toMap(), options);
  }

  Future<void> setCharge(Charge charge) {
    var options = SetOptions(merge: true);
    return _db.collection('charges').doc(charge.id).set(charge.toMap(), options);
  }

  /// Saves edits to an item's details. Shares come from the stored item, so
  /// opt-ins made while the edit screen was open aren't lost.
  Future<void> updateItemInBasket(String basketId, GroceryItem updatedItem) {
    return _mutateItems(basketId, (items) {
      final index = items.indexWhere((item) => item['id'] == updatedItem.id);
      if (index == -1) return;
      items[index] = {
        ...updatedItem.toMap(),
        'userShares': items[index]['userShares'] ?? updatedItem.userShares,
      };
    });
  }

  Future<void> deleteItemFromBasket(String basketId, String itemId) {
    return _mutateItems(basketId, (items) {
      items.removeWhere((item) => itemId == item['id']);
    });
  }

  Future<void> deleteBasket(String basketId) async {
    await _db.collection('baskets').doc(basketId).delete();
  }

  // Add a grocery item to a basket
  Future<void> addItemToBasket(String basketId, GroceryItem item) {
    return _db.collection('baskets').doc(basketId).update({
      'items': FieldValue.arrayUnion([item.toMap()])
    });
  }

  /// Adds a whole receipt's items in one write, and adds the receipt's tax to
  /// the basket so finalizing can fill it in.
  Future<void> addItemsToBasket(
    String basketId,
    List<GroceryItem> items, {
    double receiptTax = 0,
  }) {
    return _db.collection('baskets').doc(basketId).update({
      'items': FieldValue.arrayUnion(items.map((i) => i.toMap()).toList()),
      if (receiptTax > 0) 'receiptTax': FieldValue.increment(receiptTax),
    });
  }

  Future<user_dart.User> getUserById(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        return user_dart.User.fromMap(doc.data() as Map<String, dynamic>);
      } else {
        throw Exception('User not found');
      }
    } catch (e) {
      rethrow;
    }
  }

  Stream<user_dart.User> getUserStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return user_dart.User.fromMap(snapshot.data() as Map<String, dynamic>);
      } else {
        throw Exception('User not found');
      }
    });
  }

  Future<String> getUserNameById(String uid) {
    final cached = _nameCache[uid];
    if (cached != null) return cached;
    final lookup = _fetchUserName(uid);
    _nameCache[uid] = lookup;
    // Don't remember failures; try again next time.
    lookup.then((name) {
      if (name == 'Unknown User') _nameCache.remove(uid);
    });
    return lookup;
  }

  /// Names for several users at once, e.g. everyone in a basket.
  Future<Map<String, String>> getUserNames(Iterable<String> uids) async {
    final ids = uids.toSet().toList();
    final names = await Future.wait(ids.map(getUserNameById));
    return {for (var i = 0; i < ids.length; i++) ids[i]: names[i]};
  }

  Future<String> _fetchUserName(String uid) async {
    try {
      QuerySnapshot querySnapshot = await _db
          .collection('users')
          .where('id', isEqualTo: uid)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first['userName'];
      } else {
        // Their profile is gone: they deleted their account.
        return kDeletedUserName;
      }
    } catch (e) {
      return 'Unknown User';
    }
  }

  // Update a grocery item in a basket (e.g., after changes)
  Future<void> updateBasketItems(String basketId, List<GroceryItem> items) {
    return _db.collection('baskets').doc(basketId).update({
      'items': items.map((item) => item.toMap()).toList(),
    });
  }

  Future<void> updateBasketMembers(String basketId, List<String> memberIds) {
    return _db
        .collection('baskets')
        .doc(basketId)
        .update({'memberIds': memberIds});
  }

  /// Someone's device token for notifications, or '' when they have none
  /// (including when they've deleted their account).
  Future<String> getUserTokenById(String id) async {
    final doc = await _db.collection('users').doc(id).get();
    return (doc.data()?['token'] as String?) ?? '';
  }

  Future<void> sendFriendRequest(String senderId, String receiverId) async {
    await _db.collection('users').doc(senderId).update({
      'outgoingFriendRequests': FieldValue.arrayUnion([receiverId]),
    });
    await _db.collection('users').doc(receiverId).update({
      'incomingFriendRequests': FieldValue.arrayUnion([senderId]),
    });

    user_dart.User receiver = await getUserById(receiverId);
    user_dart.User sender = await getUserById(senderId);

    String title = "Friend Request";
    String body = "${sender.userName} has sent you a friend request!";

    sendNotification(title, body, [receiver.token]);

  }

  void setToken(String userId, String token){
    _db.collection('users').doc(userId).update({
      'token': token,
    });
  }

  Future<void> acceptFriendRequest(String currentUserId, String senderId) async {
    // Remove senderId from current user's incomingFriendRequests
    await _db.collection('users').doc(currentUserId).update({
      'incomingFriendRequests': FieldValue.arrayRemove([senderId]),
      'friendIds': FieldValue.arrayUnion([senderId]),
    });

    // Remove currentUserId from sender's outgoingFriendRequests
    await _db.collection('users').doc(senderId).update({
      'outgoingFriendRequests': FieldValue.arrayRemove([currentUserId]),
      'friendIds': FieldValue.arrayUnion([currentUserId]),
    });

    user_dart.User currentUser = await getUserById(currentUserId);
    user_dart.User sender = await getUserById(senderId);

    String title = "New Friend!";
    String body = "${currentUser.userName} has accepted your friend request!";

    sendNotification(title, body, [sender.token]);

  }

  Future<void> declineFriendRequest(String currentUserId, String senderId) async {
    await _db.collection('users').doc(currentUserId).update({
      'incomingFriendRequests': FieldValue.arrayRemove([senderId]),
    });
    await _db.collection('users').doc(senderId).update({
      'outgoingFriendRequests': FieldValue.arrayRemove([currentUserId]),
    });
  }

  Stream<int> getFriendRequestCount(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        List<dynamic> incomingRequests =
            snapshot.data()!['incomingFriendRequests'] ?? [];
        return incomingRequests.length;
      }
      return 0;
    });
  }

  Future<void> inviteFriendsToBasket(String basketId, List<String> friendIds) async {
    await _db.collection('baskets').doc(basketId).update({
      'invitedUserIds': FieldValue.arrayUnion(friendIds),
    });
    Basket basket = await getBasketById(basketId);
    for (String friendId in friendIds) {
      user_dart.User user = await getUserById(friendId);

      String title = "Basket Invite";
      String body = "You have been invited you to join the basket ${basket.name}!";

      sendNotification(title, body, [user.token]);
    }
  }

  Stream<List<Basket>> getUserBaskets(String userId) {
    return _db
        .collection('baskets')
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Basket.fromMap(doc.data())).toList());
  }

  Future<List<user_dart.User>> getBasketUsers(String basketId) async{
    Basket basket = await getBasketById(basketId);
    List<user_dart.User> basketUsers = [];
    for (var basketMemberId in basket.memberIds){
      user_dart.User user = await getUserById(basketMemberId);
      basketUsers.add(user);
    }
    return basketUsers;
  }

  Future<double> calculateTotalBasketPrice(String basketId) async{
    Basket basket = await getBasketById(basketId);
    double cost = 0;
    for (var item in basket.items) {
      cost += item.quantity * item.price;
    }
    return cost;
  }

  /// Turns the basket into charges and deletes it. [taxTotal] is the sales tax
  /// in dollars, split across taxable items (see computeCharges).
  Future<void> finalizeBasket(Basket basket, double taxTotal) async {
    final now = DateTime.now();
    final charges = computeCharges(basket.items, taxTotal).map((line) => Charge(
          id: Uuid().v4(),
          payerId: line.payerId,
          payeeId: line.payeeId,
          amount: line.amount,
          item: line.item ??
              GroceryItem(
                id: Uuid().v4(),
                name: "Tax",
                price: line.taxRate,
                quantity: 1,
                addedBy: line.payeeId,
                userShares: {},
                paidBy: "me",
              ),
          date: now,
          isTax: line.isTax,
        ));

    // Write every charge before anything else, in as few batches as allowed.
    var batch = _db.batch();
    var ops = 0;
    for (final charge in charges) {
      batch.set(_db.collection('charges').doc(charge.id), charge.toMap());
      if (++ops == 450) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }
    await batch.commit();

    // Notify while the basket still exists: the server checks that the host
    // shares a basket with everyone it notifies.
    try {
      await sendNotification(
        "Basket Finalized!",
        "${basket.name} has been finalized. Check your charges!",
        basket.memberTokens,
      );
    } catch (_) {
      // A failed notification shouldn't stop the basket from finalizing.
    }
    await deleteBasket(basket.id);
  }


  Future<void> declineAllRequests(String payeeId, String payerId) async {
    QuerySnapshot snapshot = await _db
        .collection('charges')
        .where('payeeId', isEqualTo: payeeId)
        .where('payerId', isEqualTo: payerId)
        .where('status', isEqualTo: 'requested')
        .get();

    WriteBatch batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {
        'requestedBy': '',
        'status': 'pending',
      });
    }
    await batch.commit();
  }


  Stream<List<Charge>> getChargesBetweenUsers(String currentUserId, String otherUserId) {
    return _db
        .collection('charges')
        .where('payerId', whereIn: [currentUserId, otherUserId])
        .where('payeeId', whereIn: [currentUserId, otherUserId])
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Charge.fromMap(doc.data());
      }).toList();
    });
  }

  Stream<List<Charge>> getCharges(String userId) {
    return _db
        .collection('charges')
        .where('involvedUserIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Charge.fromMap(doc.data())).toList());
  }

  Stream<List<AggregatedCharge>> getUniqueCharges(String userId) {
    return getCharges(userId).map((charges) {
      Map<String, double> netAmounts = {};
      Map<String, bool> allChargesRequested = {};

      for (var charge in charges) {
        String otherUserId =
        charge.payerId == userId ? charge.payeeId : charge.payerId;
        double amount = charge.amount;

        if (charge.payerId == userId) {
          netAmounts[otherUserId] = (netAmounts[otherUserId] ?? 0) + amount;
          allChargesRequested[otherUserId] =
              charge.status == 'requested' && (allChargesRequested[otherUserId] ?? true);
        } else if (charge.payeeId == userId) {
          netAmounts[otherUserId] = (netAmounts[otherUserId] ?? 0) - amount;
          allChargesRequested[otherUserId] =
              charge.status == 'requested' && (allChargesRequested[otherUserId] ?? true);
        }
      }

      return netAmounts.entries.map((entry) {
        return AggregatedCharge(
          otherUserId: entry.key,
          netAmount: entry.value,
          requested: allChargesRequested[entry.key] ?? false,
        );
      }).toList();
    });
  }

  /// Sets one user's share of an item. A manual share of 0 opts them out;
  /// isManual: false opts them in to split whatever's left equally.
  Future<void> setUserShare(
      String basketId,
      GroceryItem item, {
        required String currentUserId,
        required double newShare,
        required bool isManual,
      }) {
    return _mutateItems(basketId, (items) {
      final index = items.indexWhere((i) => i['id'] == item.id);
      if (index == -1) return;
      items[index]['userShares'] = withShare(
        Map<String, dynamic>.from(items[index]['userShares'] ?? {}),
        currentUserId,
        share: newShare,
        isManual: isManual,
      );
    });
  }

  /// Opts [uid] in or out of several items at once.
  Future<void> setOptIn(
    String basketId,
    Iterable<String> itemIds,
    String uid, {
    required bool optedIn,
  }) {
    final ids = itemIds.toSet();
    return _mutateItems(basketId, (items) {
      for (final item in items.where((i) => ids.contains(i['id']))) {
        final shares = Map<String, dynamic>.from(item['userShares'] ?? {});
        item['userShares'] =
            optedIn ? withOptIn(shares, uid) : withOptOut(shares, uid);
      }
    });
  }

  /// Splits each item equally between [memberIds], replacing existing shares.
  Future<void> splitEvenly(
    String basketId,
    Iterable<String> itemIds,
    List<String> memberIds,
  ) {
    final ids = itemIds.toSet();
    return _mutateItems(basketId, (items) {
      for (final item in items.where((i) => ids.contains(i['id']))) {
        item['userShares'] = evenShares(memberIds);
      }
    });
  }

  Stream<List<Basket>> getInvitedBaskets(String userId) {
    return _db
        .collection('baskets')
        .where('invitedUserIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Basket.fromMap(doc.data())).toList());
  }

  Future<void> acceptBasketInvitation(String basketId, String userId) async {
    String? memberToken = await getUserTokenById(userId);
    await _db.collection('baskets').doc(basketId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
      'memberTokens': FieldValue.arrayUnion([memberToken]),
      'invitedUserIds': FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> declineBasketInvitation(String basketId, String userId) async {
    await _db.collection('baskets').doc(basketId).update({
      'invitedUserIds': FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> removeFriend(String currentUserId, String friendId) async {
    await _db.collection('users').doc(currentUserId).update({
      'friendIds': FieldValue.arrayRemove([friendId]),
    });
    await _db.collection('users').doc(friendId).update({
      'friendIds': FieldValue.arrayRemove([currentUserId]),
    });
  }

  Future<Charge> getChargeById(String id) async {
    try {
      DocumentSnapshot doc = await _db.collection('charges').doc(id).get();
      if (doc.exists) {
        return Charge.fromMap(doc.data() as Map<String, dynamic>);
      } else {
        throw Exception('Charge not found');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resolveCharge(String chargeId) async {
    Charge charge = await getChargeById(chargeId);
    await _db.collection('charges').doc(chargeId).delete();

    String title = "Charge resolved!";
    String userName = await getUserNameById(charge.payeeId);
    String body = "$userName resolved the charge!";
    String token = await getUserTokenById(charge.payerId);
    sendNotification(title, body, [token]);
  }

  Future<void> requestChargeResolution(String chargeId, String currentUserId) async {
    await _db.collection('charges').doc(chargeId).update({
      'requestedBy': currentUserId,
      'status': 'requested',
    });


    Charge charge = await getChargeById(chargeId);
    String senderName = await getUserNameById(charge.payerId);
    String receiverToken = await getUserTokenById(charge.payeeId);

    String title = "Resolve Request";
    String body = "$senderName requested to resolve charge";

    sendNotification(title, body, [receiverToken]);

  }


  Future<void> resolveCharges(String payeeId, String payerId) async{
      QuerySnapshot snapshot = await _db
          .collection('charges')
          .where('payeeId', isEqualTo: payeeId)
          .where('payerId', isEqualTo: payerId)
          .get();
      WriteBatch batch = _db.batch();
      for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
      }
      await batch.commit();

      String title = "Charges resolved!";
      String name = await getUserNameById(payeeId);
      String body = "$name resolved your charges!";
      String token = await getUserTokenById(payerId);
      sendNotification(title, body, [token]);
  }

  Future<void> resolveChargesBetweenUsers(String payer, String payee) async{
    QuerySnapshot snapshot = await _db
        .collection('charges')
        .where('payeeId', isEqualTo: payee)
        .where('payerId', isEqualTo: payer)
        .get();
    WriteBatch batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Clears every charge between two people without telling anyone. For
  /// when the other person deleted their account and can't confirm a payment.
  Future<void> clearChargesWith(String currentUserId, String otherUserId) async {
    await resolveChargesBetweenUsers(currentUserId, otherUserId);
    await resolveChargesBetweenUsers(otherUserId, currentUserId);
  }

  Future<void> clearCharge(String chargeId) =>
      _db.collection('charges').doc(chargeId).delete();

  Future<void> resolveAllCharges(String currentUserId, String otherUserId) async {

    await resolveChargesBetweenUsers(currentUserId, otherUserId);
    await resolveChargesBetweenUsers(otherUserId, currentUserId);

    String title = "All Charges resolved!";
    String name = await getUserNameById(currentUserId);
    String body = "$name resolved all your charges!";
    String token = await getUserTokenById(otherUserId);
    sendNotification(title, body, [token]);

  }

  Future<void> requestResolutionForAllCharges(
      String currentUserId, String otherUserId) async {
    QuerySnapshot snapshot = await _db
        .collection('charges')
        .where('payerId', isEqualTo: currentUserId)
        .where('payeeId', isEqualTo: otherUserId)
        .where('status', isEqualTo: 'pending')
        .get();
    WriteBatch batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {
        'requestedBy': currentUserId,
        'status': 'requested',
      });
    }
    await batch.commit();

    String title = "Requested Charges Resolved";
    String name = await getUserNameById(currentUserId);
    String body = "$name has requested to resolve all charges";
    String token = await getUserTokenById(otherUserId);
    sendNotification(title, body, [token]);
  }
  Stream<List<AggregatedResolutionRequest>> getUniquePendingResolutionRequests(String userId){
    // We look for charges where:
    //   - payeeId = userId
    //   - status = 'requested'
    // Then we group them by the 'requestedBy' field and sum the amounts.
    return _db
        .collection('charges')
        .where('payeeId', isEqualTo: userId)
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .map((snapshot) {
      // Convert each document into a Charge object
      final charges = snapshot.docs
          .map((doc) => Charge.fromMap(doc.data()))
          .toList();

      // Aggregate by requestedBy
      Map<String, AggregatedResolutionRequest> aggregatedMap = {};

      for (var charge in charges) {
        final requester = charge.requestedBy;
        if (requester.isEmpty) continue; // skip if somehow blank
        if (aggregatedMap.containsKey(requester)){
          aggregatedMap[requester]?.totalAmountRequested += charge.amount;
        }else{
          aggregatedMap[requester] = AggregatedResolutionRequest(requestedBy: requester, totalAmountRequested: charge.amount, chargeIds: [charge.id]);
        }
      }

      // Convert the map into a list of AggregatedResolutionRequest objects
      return aggregatedMap.entries.map((entry) {
        return entry.value;
      }).toList();
    });
  }


  Stream<int> getPendingRequestCount(String userId) {
    return _db
        .collection('charges')
        .where('payeeId', isEqualTo: userId)
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<List<Charge>> getPendingResolutionRequests(String userId) {
    return _db
        .collection('charges')
        .where('payeeId', isEqualTo: userId)
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Charge.fromMap(doc.data())).toList());
  }

  Future<void> acceptChargeResolution(String chargeId) async {
    await resolveCharge(chargeId);

  }

  Future<void> declineChargeResolution(String chargeId) async {
    await _db.collection('charges').doc(chargeId).update({
      'requestedBy': '',
      'status': 'pending',
    });
  }

  Future<void> declineRequests(String payeeId, AggregatedResolutionRequest request) async {
    QuerySnapshot snapshot = await _db
        .collection('charges')
        .where('payeeId', isEqualTo: payeeId)
        .where('payerId', isEqualTo: request.requestedBy)
        .where('status', isEqualTo: 'requested')
        .get();

    WriteBatch batch = _db.batch();
    for (var doc in snapshot.docs) {
      if (request.chargeIds.contains(doc.id)) {
        batch.update(doc.reference, {
          'requestedBy': '',
          'status': 'pending',
        });
      }
    }
    await batch.commit();
  }
}
