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
  // Sales tax from receipts imported into this basket. Only ever changed with
  // FieldValue.increment, so it isn't written by toMap().
  final double receiptTax;
  // Each imported receipt's own tax, by trip id (see Trip). Also only ever
  // changed with FieldValue.increment. receiptTax still counts it too, so
  // older versions of the app see the right total.
  final Map<String, double> tripTax;

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
    this.receiptTax = 0,
    this.tripTax = const {},
  });

  /// Tax that isn't tied to a receipt: from receipts imported before trips
  /// existed. Split across the items that didn't come from a receipt.
  double get otherTax {
    final left = receiptTax - tripTax.values.fold(0.0, (s, t) => s + t);
    return left < 0.005 ? 0 : left;
  }

  static Map<String, double> _tripTax(Object? map) => map is Map
      ? {
          for (final e in map.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
        }
      : const {};

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
      receiptTax: (map['receiptTax'] as num?)?.toDouble() ?? 0,
      tripTax: _tripTax(map['tripTax']),
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
      receiptTax: (data['receiptTax'] as num?)?.toDouble() ?? 0,
      tripTax: _tripTax(data['tripTax']),
    );
  }
}
