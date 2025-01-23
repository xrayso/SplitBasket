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

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

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
    var options = SetOptions(merge: true);
    return _db.collection('users').doc(user.id).set(user.toMap(), options);
  }

  Future<void> setCharge(Charge charge) {
    var options = SetOptions(merge: true);
    return _db.collection('charges').doc(charge.id).set(charge.toMap(), options);
  }

  Future<void> updateItemInBasket(String basketId, GroceryItem updatedItem) async {
    DocumentReference basketRef = _db.collection('baskets').doc(basketId);
    DocumentSnapshot basketSnapshot = await basketRef.get();
    if (basketSnapshot.exists) {
      Map<String, dynamic> data = basketSnapshot.data() as Map<String, dynamic>;
      List<dynamic> items = data['items'] ?? [];
      int index = items.indexWhere((item) => item['id'] == updatedItem.id);
      if (index != -1) {
        items[index] = updatedItem.toMap();
        await basketRef.update({'items': items});
      }
    }
  }

  Future<void> deleteItemFromBasket(String basketId, String itemId) async {
    DocumentReference basketRef = _db.collection('baskets').doc(basketId);
    DocumentSnapshot basketSnapshot = await basketRef.get();
    if (basketSnapshot.exists) {
      Map<String, dynamic> data = basketSnapshot.data() as Map<String, dynamic>;
      List<dynamic> items = data['items'] ?? [];
      items.removeWhere((item) => itemId == item['id']);
      await basketRef.update({'items': items});
    }
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

  Future<String> getUserNameById(String uid) async {
    try {
      QuerySnapshot querySnapshot = await _db
          .collection('users')
          .where('id', isEqualTo: uid)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first['userName'];
      } else {
        return 'Unknown User';
      }
    } catch (e) {
      return e.toString();
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

  Future<String> getUserTokenById(String id) async{
    user_dart.User user = await getUserById(id);
    return user.token;
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

  Future<void> finalizeBasket(Basket basket, double taxPercent) async {
    List<Charge> charges = _calculateCharges(basket, taxPercent);
    try {
      for (Charge charge in charges) {
        await setCharge(charge);
      }
      String title = "Basket Finalized!";
      String body = "${basket.name} has been finalized. Check your charges!";
      sendNotification(title, body, basket.memberTokens);
      // await deleteBasket(basket.id);
    } catch (e) {
      // If something goes wrong, here's just an example of adding an error item
      GroceryItem item = GroceryItem(
        id: Uuid().v4(),
        name: e.toString(),
        price: 3,
        quantity: 3,
        addedBy: "addedBy",
        userShares: {},
      );
      await addItemToBasket(basket.id, item);
    }
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


  // Updated to handle userShares as { uid: {share: double, isManual: bool} }
  List<Charge> _calculateCharges(Basket basket, double taxPercent) {
    final hostId = basket.hostId;
    Map<String, double> totalUserCosts = {};
    List<Charge> charges = [];
    for (GroceryItem item in basket.items) {
      double totalItemCost = item.price * item.quantity;
      item.userShares.forEach((userId, shareData) {
        if (userId == hostId) return;
        double fraction = (shareData['share'] ?? 0.0).toDouble();
        double userCost = totalItemCost * fraction;
        totalUserCosts[userId] = (totalUserCosts[userId] ?? 0) + userCost;
        if (userCost > 0) {
          charges.add(
            Charge(
              id: Uuid().v4(),
              payerId: userId,
              payeeId: hostId,
              amount: userCost,
              item: item,
              date: DateTime.now(),
              isTax: false,
            ),
          );
        }
      });
    }
    for (var entry in  totalUserCosts.entries){
      if (entry.value > 0) {
        double taxPrice = entry.value * taxPercent;
        charges.add(
          Charge(
            id: Uuid().v4(),
            payerId: entry.key,
            payeeId: hostId,
            amount: taxPrice,
            item: GroceryItem(id: Uuid().v4(), name: "Tax", price: taxPercent, quantity: 1, addedBy: hostId, userShares: {}),
            date: DateTime.now(),
            isTax: true
          ),
        );
      }
    }
    return charges;
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

  // --------------
  // EDITED METHOD:
  // --------------
  // Now storing user share as { 'share': double, 'isManual': bool }.
  // Recalculate auto-shares after setting any share.
  Future<void> setUserShare(
      String basketId,
      GroceryItem item, {
        required String currentUserId,
        required double newShare,
        required bool isManual,
      }) async {
    final basketRef = _db.collection('baskets').doc(basketId);
    final basketSnapshot = await basketRef.get();
    if (!basketSnapshot.exists) return;

    List<dynamic> items = basketSnapshot.get('items') ?? [];
    int index = items.indexWhere((i) => i['id'] == item.id);
    if (index == -1) return;

    Map<String, dynamic> userShares = Map<String, dynamic>.from(
      items[index]['userShares'] ?? {},
    );

    if (newShare == 0.0 && isManual) {
      userShares.remove(currentUserId);
    } else {
      userShares[currentUserId] = {
        'share': newShare,
        'isManual': isManual,
      };
    }

    items[index]['userShares'] = userShares;
    await basketRef.update({'items': items});

    // Recalculate auto-shares after the update
    await _recalculateAutoShares(basketRef, item.id);
  }

  /// Recalculate shares for all users with isManual=false.
  /// leftover = 1.0 - sum of all manual shares.
  /// Distribute leftover equally among auto users.
  Future<void> _recalculateAutoShares(DocumentReference basketRef, String itemId) async {
    final snap = await basketRef.get();
    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>;
    List<dynamic> items = data['items'] ?? [];
    final idx = items.indexWhere((i) => i['id'] == itemId);
    if (idx == -1) return;

    Map<String, dynamic> userShares =
    Map<String, dynamic>.from(items[idx]['userShares'] ?? {});

    double totalManual = 0.0;
    List<String> autoUsers = [];

    userShares.forEach((uid, data) {
      final share = (data['share'] ?? 0.0).toDouble();
      final manual = (data['isManual'] ?? false) == true;
      if (manual) {
        totalManual += share;
      } else {
        autoUsers.add(uid);
      }
    });

    double leftover = 1.0 - totalManual;
    if (leftover < 0) leftover = 0.0; // clamp if manual shares exceed 1.0

    if (autoUsers.isEmpty || leftover <= 0) {
      // If leftover is 0 or negative, auto users get 0
      for (String uid in autoUsers) {
        userShares[uid] = {
          'share': 0.0,
          'isManual': false,
        };
      }
    } else {
      double eachAutoShare = leftover / autoUsers.length;
      for (String uid in autoUsers) {
        userShares[uid] = {
          'share': eachAutoShare,
          'isManual': false,
        };
      }
    }

    items[idx]['userShares'] = userShares;
    await basketRef.update({'items': items});
  }

  Stream<List<Basket>> getInvitedBaskets(String userId) {
    return _db
        .collection('baskets')
        .where('invitedUserIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Basket.fromMap(doc.data())).toList());
  }

  Future<void> acceptBasketInvitation(String basketId, String userId) async {
    String? memberToken = await _messaging.getToken();
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


  Future<void> resolveCharges(String currentUserId, AggregatedResolutionRequest request) async{
      QuerySnapshot snapshot = await _db
          .collection('charges')
          .where('payeeId', isEqualTo: currentUserId)
          .where('payerId', isEqualTo: request.requestedBy)
          .get();
      WriteBatch batch = _db.batch();
      for (var doc in snapshot.docs) {
        if (request.chargeIds.contains(doc.id)) {
          batch.delete(doc.reference);
        }
      }
      await batch.commit();

      String title = "Charges resolved!";
      String name = await getUserNameById(currentUserId);
      String body = "$name resolved your charges!";
      String token = await getUserTokenById(request.requestedBy);
      sendNotification(title, body, [token]);
  }

  Future<void> resolveAllCharges(String currentUserId, String otherUserId) async {
    QuerySnapshot snapshot = await _db
        .collection('charges')
        .where('payeeId', isEqualTo: currentUserId)
        .where('payerId', isEqualTo: otherUserId)
        .get();
    WriteBatch batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

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
