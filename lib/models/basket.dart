import 'package:cloud_firestore/cloud_firestore.dart';

import 'grocery_item.dart';

class Basket {
  final String id;
  final String name;
  final String hostId;
  final List<String> memberIds;
  final List<String> memberTokens;
  List<GroceryItem> items;
  final Map<String, double>? charges;
  final String invitationCode;
  final List<String> invitedUserIds;

  Basket({
    required this.id,
    required this.name,
    required this.hostId,
    required this.memberIds,
    required this.memberTokens,
    this.items = const [],
    this.charges,
    required this.invitationCode,
    this.invitedUserIds = const [],
  });

  // Convert Basket to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'hostId': hostId,
      'memberIds': memberIds,
      'memberTokens': memberTokens,
      // Store items as a list of maps
      if (charges != null) 'charges': charges,
      'invitationCode': invitationCode,
      'invitedUserIds': invitedUserIds,
    };
  }

  // Create Basket from Map
  factory Basket.fromMap(Map<String, dynamic> map) {

    return Basket(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      hostId: map['hostId'] ?? '',
      memberIds: map['memberIds'] != null
          ? List<String>.from(map['memberIds'])
          : [],
      memberTokens: map['memberTokens'] != null
          ? List<String>.from(map['memberTokens'])
          : [],
      items: map['items'] != null
          ? List<Map<String, dynamic>>.from(map['items'])
          .map((itemMap) => GroceryItem.fromMap(itemMap))
          .toList()
          : [],
      charges: map['charges'] != null
          ? Map<String, double>.from(map['charges'])
          : null,
      invitationCode: map['invitationCode'] ?? '',
      invitedUserIds: map['invitedUserIds'] != null ?
      List<String>.from(map['invitedUserIds']): [],
    );
  }
  factory Basket.fromDocument(DocumentSnapshot doc, items) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Basket(
      id: doc.id,
      items: items,
      name: data['name'] ?? '',
      hostId: data['hostId'] ?? '',
      charges: data['charges'] != null
          ? Map<String, double>.from(data['charges'])
          : null,
      memberIds: List<String>.from(data['memberIds'] ?? []),
      memberTokens: List<String>.from(data['memberTokens'] ?? []),
      invitationCode: data['invitationCode'] ?? '',
      invitedUserIds: data['invitedUserIds'] != null ?
      List<String>.from(data['invitedUserIds']): [],
    );
  }
}
