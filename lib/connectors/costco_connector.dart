import 'package:flutter/material.dart';

import '../screens/receipt_review_screen.dart' show ReceiptLine;
import '../services/costco_receipts.dart';
import 'receipt_connector.dart';

/// In-warehouse receipts from costco.ca, read from the same API Costco's own
/// Orders & Purchases page uses (see costco_receipts.dart).
class CostcoConnector extends ReceiptConnector {
  const CostcoConnector();

  @override
  String get id => 'costco';

  @override
  String get name => 'Costco';

  @override
  String get description => 'In-warehouse receipts from your Costco.ca account';

  @override
  IconData get icon => Icons.warehouse_outlined;

  // "Orders & Purchases": sends people through Costco's sign-in first if
  // needed, and leaves the page holding the tokens the receipts API wants.
  @override
  Uri get startUrl => Uri.parse('https://www.costco.ca/OrderStatusCmd');

  @override
  bool isStorePage(Uri url) =>
      url.host == 'costco.ca' || url.host.endsWith('.costco.ca');

  @override
  String fetchReceiptsJs() => costcoFetchReceiptsJs(daysBack: 90);

  // Costco names warehouses in capitals ("KINGSTON").
  static String _titleCase(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  ConnectedReceipt parseReceipt(Map<String, dynamic> json) {
    final receipt = CostcoReceipt.fromJson(json);
    return ConnectedReceipt(
      id: receipt.barcode,
      store: name,
      date: receipt.date,
      place: _titleCase(receipt.warehouse),
      total: receipt.total,
      tax: receipt.taxes,
      itemCount: receipt.items.length,
      lines: () => receipt.items
          .map((i) => ReceiptLine(
                description: i.description,
                receiptText: i.description,
                qty: i.qty,
                total: i.total,
                taxable: i.taxable,
                code: i.itemNumber,
                discount: i.discount,
              ))
          .toList(),
    );
  }
}
