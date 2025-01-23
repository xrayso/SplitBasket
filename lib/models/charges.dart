import 'package:cloud_firestore/cloud_firestore.dart';

import 'grocery_item.dart';

class Charge{

  final String id;
  final String payerId;
  final String payeeId;
  final double amount;
  final GroceryItem item;
  final DateTime date;
  final bool isTax;
  String status;
  String requestedBy;
  Charge({
    required this.id,
    required this.payerId,
    required this.payeeId,
    required this.amount,
    required this.item,
    required this.date,
    required this.isTax,
    this.status = "pending",
    this.requestedBy = '',

  });

  factory Charge.fromMap(Map<String, dynamic> data) {
    return Charge(
      id: data['id'],
      payerId: data['payerId'],
      payeeId: data['payeeId'],
      amount: data['amount'].toDouble(),
      item: GroceryItem.fromMap(data['item']),
      isTax: data['isTax'],
      date: (data['date'] as Timestamp).toDate(),
      status: data['status'] ?? 'pending',
      requestedBy: data['requestedBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'payerId': payerId,
      'payeeId': payeeId,
      'amount': amount,
      'item': item.toMap(),
      'date': Timestamp.fromDate(date),
      'involvedUserIds': [payeeId, payerId],
      'status': status,
      'isTax': isTax,
      'requestedBy': requestedBy,
    };
  }



}