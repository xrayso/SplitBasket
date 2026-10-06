import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/receipt_review_screen.dart' show ReceiptLine;

/// A store people can connect to import their receipts: they sign in to their
/// account on the store's own website, inside the app, and the app reads
/// their receipts from that page.
///
/// To add a store, subclass this and add it to `receiptConnectors` in
/// connections.dart. The Connections tab, the sign-in page, the receipt list
/// and importing into a basket all work from these few members.
abstract class ReceiptConnector {
  const ReceiptConnector();

  /// Stable id, used to remember the connection on this phone.
  String get id;

  String get name;

  /// One line under the name on the Connections tab.
  String get description;

  IconData get icon;

  /// A page on the store's site that sends people through its sign-in first,
  /// and once they're signed in holds what [fetchReceiptsJs] needs.
  Uri get startUrl;

  /// Whether [url] is one of the store's own pages, where [fetchReceiptsJs]
  /// can run (as opposed to a sign-in page on another domain).
  bool isStorePage(Uri url);

  /// JavaScript run inside a store page. It must post one JSON message to the
  /// `ReceiptBridge` channel: `{status: 'ok', receipts: [...]}`,
  /// `{status: 'signedOut'}`, or `{status: 'error', message: '...'}`.
  String fetchReceiptsJs();

  /// Turns one entry of an 'ok' message's `receipts` into a receipt.
  ConnectedReceipt parseReceipt(Map<String, dynamic> json);
}

/// A receipt read from a connected store.
class ConnectedReceipt {
  /// The store's own id for it, so the app can tell which were imported.
  final String id;
  final String store;
  final DateTime? date;

  /// Which location, e.g. the warehouse.
  final String place;
  final double total;
  final double tax;
  final int itemCount;
  final List<ReceiptLine> Function() _lines;

  ConnectedReceipt({
    required this.id,
    required this.store,
    required this.date,
    required this.place,
    required this.total,
    required this.tax,
    required this.itemCount,
    required List<ReceiptLine> Function() lines,
  }) : _lines = lines;

  /// Fresh lines each time: importing edits them (names, who's in).
  List<ReceiptLine> lines() => _lines();

  /// What the items came to before tax, when the store says.
  double? get subtotal => total > 0 ? total - tax : null;

  /// e.g. "Costco · Oct 3"
  String get title =>
      date == null ? store : '$store · ${DateFormat('MMM d').format(date!)}';
}
