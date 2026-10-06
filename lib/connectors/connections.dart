import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'costco_connector.dart';
import 'receipt_connector.dart';

/// Every store people can connect, in the order the Connections tab lists
/// them.
const List<ReceiptConnector> receiptConnectors = [CostcoConnector()];

/// What this phone remembers about each connection: when its receipts last
/// loaded and which ones were imported. The sign-in itself is the store's
/// own, kept in the in-app browser's cookies and storage.
class Connections {
  Connections._();

  /// Bumps whenever a connection changes, so screens showing them can update.
  static final changes = ValueNotifier<int>(0);

  static String _key(ReceiptConnector c, String what) =>
      'connection.${c.id}.$what';

  /// When receipts last loaded, or null when not connected.
  static Future<DateTime?> lastSynced(ReceiptConnector c) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key(c, 'synced'));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> markSynced(ReceiptConnector c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _key(c, 'synced'), DateTime.now().millisecondsSinceEpoch);
    changes.value++;
  }

  /// The store signed them out, e.g. its session ran out.
  static Future<void> markSignedOut(ReceiptConnector c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(c, 'synced'));
    changes.value++;
  }

  static Future<Set<String>> imported(ReceiptConnector c) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(c, 'imported')) ?? const []).toSet();
  }

  static Future<void> markImported(ReceiptConnector c, String receiptId) async {
    if (receiptId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key(c, 'imported')) ?? [])
      ..remove(receiptId)
      ..add(receiptId);
    // Stores only show recent receipts, so old ids can go.
    await prefs.setStringList(_key(c, 'imported'),
        ids.length > 200 ? ids.sublist(ids.length - 200) : ids);
    changes.value++;
  }

  /// Signs out of every connected store on this phone and forgets them. The
  /// in-app browser keeps one set of cookies for all sites, so this can't
  /// sign out of just one store.
  static Future<void> disconnectAll() async {
    try {
      await WebViewCookieManager().clearCookies();
      await WebViewController().clearLocalStorage();
    } catch (e) {
      // Never let this stop a sign-out or account deletion.
      debugPrint("Couldn't clear store sign-ins: $e");
    }
    final prefs = await SharedPreferences.getInstance();
    for (final c in receiptConnectors) {
      await prefs.remove(_key(c, 'synced'));
      await prefs.remove(_key(c, 'imported'));
    }
    changes.value++;
  }
}
