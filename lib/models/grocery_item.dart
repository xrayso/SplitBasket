class GroceryItem {
  final String id;
  final String name;
  final double price;
  final int quantity;
  final String addedBy;
  final List<String> optedInUserIds;

  GroceryItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.addedBy,
    List<String>? optedInUserIds,
  }) : optedInUserIds = optedInUserIds ?? [];

  // Convert a GroceryItem into a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'quantity': quantity,
      'addedBy': addedBy,
      'optedInUserIds': optedInUserIds,
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
      optedInUserIds: map['optedInUserIds'] != null
          ? List<String>.from(map['optedInUserIds'])
          : [],
    );
  }

}