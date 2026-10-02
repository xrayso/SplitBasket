import 'package:cloud_firestore/cloud_firestore.dart';

class GroceryItem {
  final String id;
  final String name;
  final double price;
  final int quantity;
  final String addedBy;
  final String paidBy;
  final Map<String, dynamic> userShares;
  // Whether sales tax was charged on this item. When any item in a basket is
  // taxable, the basket's tax is split across taxable items only.
  final bool taxable;
  // One of kItemCategories, or null when unknown.
  final String? category;

  GroceryItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.addedBy,
    required this.paidBy,
    required this.userShares,
    this.taxable = false,
    this.category,
  });

  // Convert a GroceryItem into a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'quantity': quantity,
      'addedBy': addedBy,
      'userShares': userShares,
      'paidBy': paidBy,
      'taxable': taxable,
      if (category != null) 'category': category,
    };
  }

  // Create a GroceryItem from a Firestore Document Snapshot
  factory GroceryItem.fromMap(Map<String, dynamic> map) {
    return GroceryItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      price: map['price'] != null ? (map['price'] as num).toDouble() : 0.0,
      quantity: map['quantity'] ?? 0,
      addedBy: map['addedBy'] ?? '',
      paidBy: map['paidBy'] ?? '',
      userShares: Map<String, dynamic>.from(map['userShares'] ?? {}
      ),
      taxable: map['taxable'] == true,
      category: map['category'] as String?,
    );
  }
  factory GroceryItem.fromDocument(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return GroceryItem.fromMap(data);
  }

  GroceryItem copyWith({
    String? name,
    double? price,
    int? quantity,
    String? paidBy,
    Map<String, dynamic>? userShares,
    bool? taxable,
    String? category,
  }) {
    return GroceryItem(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      addedBy: addedBy,
      paidBy: paidBy ?? this.paidBy,
      userShares: userShares ?? this.userShares,
      taxable: taxable ?? this.taxable,
      category: category ?? this.category,
    );
  }

  double get total => price * quantity;

  /// Fraction of this item the given user is paying for (0 when not opted in).
  double shareOf(String uid) {
    final data = userShares[uid];
    if (data is! Map) return 0.0;
    return ((data['share'] ?? 0.0) as num).toDouble();
  }

  /// Nobody has opted in yet, so the basket can't be finalized.
  bool get needsSomeone =>
      !userShares.values.any((d) => d is Map && ((d['share'] ?? 0) as num) > 0);
}

/// Categories the receipt reader sorts items into, with their display names.
const kItemCategories = <String, String>{
  'produce': 'Produce',
  'meat_seafood': 'Meat & seafood',
  'dairy_eggs': 'Dairy & eggs',
  'bakery': 'Bakery',
  'frozen': 'Frozen',
  'pantry': 'Pantry',
  'snacks': 'Snacks',
  'beverages': 'Drinks',
  'household': 'Household',
  'personal_care': 'Personal care',
  'other': 'Other',
};
