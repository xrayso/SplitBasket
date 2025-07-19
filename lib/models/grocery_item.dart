import 'package:cloud_firestore/cloud_firestore.dart';

class GroceryItem {
  final String id;
  final String name;
  final double price;
  final int quantity;
  final String addedBy;
  final String paidBy;
  final Map<String, dynamic> userShares;

  GroceryItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.addedBy,
    required this.paidBy,
    required this.userShares,
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
    );
  }
  factory GroceryItem.fromDocument(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return GroceryItem.fromMap(data);
  }
}