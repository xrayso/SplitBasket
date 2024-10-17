import 'grocery_item.dart';

class Basket {
  final String id;
  final String name;
  final String hostId;
  final List<String> memberIds;
  final List<GroceryItem> items;
  final Map<String, double>? charges;
  final String invitationCode;
  final List<String> invitedUserIds;

  Basket({
    required this.id,
    required this.name,
    required this.hostId,
    required this.memberIds,
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
      // Store items as a list of maps
      'items': items.map((item) => item.toMap()).toList(),
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
      List<String>.from(map['invitedUserIds']):
      [],
    );
  }
}
