import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../models/charges.dart';
import '../models/aggregated_charge.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Create or update a basket
  Future<void> setBasket(Basket basket) {
    var options = SetOptions(merge: true);

    return _db
        .collection('baskets')
        .doc(basket.id)
        .set(basket.toMap(), options);
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

  Future<void> setUser(User user) {
    var options = SetOptions(merge: true);
    return _db
        .collection('users')
        .doc(user.id)
        .set(user.toMap(), options);
  }

  Future<void> setCharge(Charge charge){
    var options = SetOptions(merge: true);
    return _db
        .collection('charges')
        .doc(charge.id)
        .set(charge.toMap(), options);
  }

  Future<void> updateItemInBasket(String basketId,
      GroceryItem updatedItem) async {
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
  Future<void> deleteBasket(String basketId) async{
    _db
        .collection('baskets')
        .doc(basketId)
        .delete();
  }
  // Add a grocery item to a basket
  Future<void> addItemToBasket(String basketId, GroceryItem item) {
    return _db.collection('baskets').doc(basketId).update({
      'items': FieldValue.arrayUnion([item.toMap()])
    });
  }

  Future<User> getUserById(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        return User.fromMap(doc.data() as Map<String, dynamic>);
      } else {
        print("HELLO");
        throw Exception('User not found');
      }
    } catch (e) {
      rethrow;
    }
  }

  Stream<User> getUserStream(String uid){
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists) {
        return User.fromMap(snapshot.data() as Map<String, dynamic>);
      } else {
        throw Exception('User not found');
      }
    });
  }

  Future<String> getUserNameById(String uid) async {
    try {
      // Query the users collection to find the document where the 'id' field matches the provided uid
      QuerySnapshot querySnapshot = await _db
          .collection('users')
          .where('id', isEqualTo: uid)
          .limit(1) // Ensure that we only get one result
          .get();

      // Check if a document was found
      if (querySnapshot.docs.isNotEmpty) {
        // Extract the username from the document
        return querySnapshot.docs.first['userName'];
      } else {
        // Return a default value or throw an error if the user was not found
        return 'Unknown User';
      }
    } catch (e) {
      // Handle the error (e.g., log it)
      return e
          .toString(); // Optionally, return a fallback value in case of an error
    }
  }

  // Update a grocery item in a basket (e.g., opt-in changes)
  Future<void> updateBasketItems(String basketId, List<GroceryItem> items) {
    return _db.collection('baskets').doc(basketId).update({
      'items': items.map((item) => item.toMap()).toList(),
    });
  }
  Future<void> updateBasketMembers(String basketId, List<String>memberIds){
    return _db.collection('baskets').doc(basketId).update({
      'memberIds': memberIds
    });
  }




  Future<void> sendFriendRequest(String senderId, String receiverId) async{
    await _db.collection('users').doc(senderId).update({
      'outgoingFriendRequests': FieldValue.arrayUnion([receiverId]),
    });
    await _db.collection('users').doc(receiverId).update({
      'incomingFriendRequests': FieldValue.arrayUnion([senderId]),
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
  }

  Future<void> declineFriendRequest(String currentUserId, String senderId) async {
    // Remove senderId from current user's incomingFriendRequests
    await _db.collection('users').doc(currentUserId).update({
      'incomingFriendRequests': FieldValue.arrayRemove([senderId]),
    });

    // Remove currentUserId from sender's outgoingFriendRequests
    await _db.collection('users').doc(senderId).update({
      'outgoingFriendRequests': FieldValue.arrayRemove([currentUserId]),
    });
  }

  Stream<int> getFriendRequestCount(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        List<dynamic> incomingRequests = snapshot.data()!['incomingFriendRequests'] ?? [];
        return incomingRequests.length;
      }
      return 0;
    });
  }

  Future<void> inviteFriendsToBasket(String basketId, List<String> friendIds) async{
    await _db.collection('baskets').doc(basketId).update({
      'invitedUserIds': FieldValue.arrayUnion(friendIds),
    });
  }

  Stream<List<Basket>> getUserBaskets(String userId) {
    return _db
        .collection('baskets')
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => Basket.fromMap(doc.data()))
            .toList());
  }


  Future<void> finalizeBasket(Basket basket) async {

    List<Charge> charges = _calculateCharges(basket);
    try {
      for (Charge charge in charges) {
        await setCharge(charge);
      }
      await deleteBasket(basket.id);
    }catch (e) {
      GroceryItem item = GroceryItem(id: Uuid().v4(),
          name: e.toString(),
          price: 3,
          quantity: 3,
          addedBy: "addedBy");
      await addItemToBasket(basket.id, item);
    }
  }

  List<Charge> _calculateCharges(Basket basket) {
    final hostId = basket.hostId;
    List<Charge> charges = [];
    for (GroceryItem item in basket.items) {
      double totalItemCost = item.price * item.quantity;
      int numberOfPeople = item.optedInUserIds.length;

      double costPerPerson = totalItemCost / numberOfPeople;
      for (String userId in item.optedInUserIds) {
        if (userId == hostId) continue;
        charges.add(Charge(
            id: Uuid().v4(),
            payerId: userId,
            payeeId: hostId,
            amount: costPerPerson,
            item: item,
            date: DateTime.now())
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
        .map((snapshot) {
      return snapshot.docs.map((doc) => Charge.fromMap(doc.data())).toList();
    });
  }

  Stream<List<AggregatedCharge>> getUniqueCharges(String userId) {
    return getCharges(userId).map((charges) {
      Map<String, double> netAmounts = {};
      Map<String, bool> allChargesRequested = {};

      for (var charge in charges) {
        // Determine the other user involved in the charge
        String otherUserId =
        charge.payerId == userId ? charge.payeeId : charge.payerId;

        // Calculate the amount based on whether the user is the payer or payee
        double amount = charge.amount;
        if (charge.payerId == userId) {
          // The user owes money to the other user
          netAmounts[otherUserId] = (netAmounts[otherUserId] ?? 0) + amount;
          allChargesRequested[otherUserId] = charge.status == 'requested' && (allChargesRequested[otherUserId] ?? true);
        } else if (charge.payeeId == userId) {
          // The other user owes money to the user
          netAmounts[otherUserId] = (netAmounts[otherUserId] ?? 0) - amount;
          allChargesRequested[otherUserId] = charge.status == 'requested' && (allChargesRequested[otherUserId] ?? true);

        }
      }
      return netAmounts.entries.map((entry) {
        return AggregatedCharge(
          otherUserId: entry.key,
          netAmount: entry.value,
          requested: allChargesRequested[entry.key]!,
        );
      }).toList();
    });
  }
  Future<void> toggleOptIn(GroceryItem item, String basketId, String currentUserId) async {
    // Get the basket document
    DocumentSnapshot basketSnapshot = await _db.collection('baskets').doc(basketId).get();
    if (!basketSnapshot.exists) return;

    // Get the current list of items in the basket
    List<dynamic> items = basketSnapshot.get('items') ?? [];

    // Find the index of the item to modify
    int index = items.indexWhere((i) => i['id'] == item.id);
    if (index == -1) return; // Item not found

    // Modify the optedInUserIds array for the specific item
    List<dynamic> optedInUserIds = items[index]['optedInUserIds'] ?? [];
    if (optedInUserIds.contains(currentUserId)) {
      optedInUserIds.remove(currentUserId);
    } else {
      optedInUserIds.add(currentUserId);
    }

    // Update the item in the items array
    items[index]['optedInUserIds'] = optedInUserIds;

    // Update the basket document with the modified items array
    await _db.collection('baskets').doc(basketId).update({'items': items});
  }

  Stream<List<Basket>> getInvitedBaskets(String userId){
    return _db
        .collection('baskets')
        .where('invitedUserIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Basket.fromMap(doc.data())).toList());
  }


  Future<void> acceptBasketInvitation(String basketId, String userId) async {
    await _db.collection('baskets').doc(basketId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
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


  Future<void> resolveCharge(String chargeId) async{
    await _db.collection('charges').doc(chargeId).delete();
  }
  Future<void> requestChargeResolution(
      String chargeId, String currentUserId) async {
    await _db.collection('charges').doc(chargeId).update({
      'requestedBy': currentUserId,
      'status': 'requested',
    });
  }

  Future<void> resolveAllCharges(
      String currentUserId, String otherUserId) async {
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
        .map((snapshot) => snapshot.docs
        .map((doc) => Charge.fromMap(doc.data()))
        .toList());
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
}
