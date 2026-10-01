// Costco warehouse receipts, read from the same (undocumented) GraphQL API
// that the "Orders & Purchases" page on costco.ca / costco.com uses.
//
// The request runs *inside* the signed-in Costco web page (see
// CostcoImportScreen), so the user's Costco password and tokens never leave
// that page — nothing is sent to Firebase.

import 'dart:convert';

class CostcoLineItem {
  final String description;
  final int qty;
  final double total; // net of instant savings / coupons

  CostcoLineItem({
    required this.description,
    required this.qty,
    required this.total,
  });
}

class CostcoReceipt {
  final String barcode;
  final DateTime? date;
  final String warehouse;
  final double total;
  final double taxes;
  final List<CostcoLineItem> items;

  CostcoReceipt({
    required this.barcode,
    required this.date,
    required this.warehouse,
    required this.total,
    required this.taxes,
    required this.items,
  });

  factory CostcoReceipt.fromJson(Map<String, dynamic> json) {
    return CostcoReceipt(
      barcode: json['transactionBarcode']?.toString() ?? '',
      date: DateTime.tryParse(
          (json['transactionDateTime'] ?? json['transactionDate'] ?? '')
              .toString()),
      warehouse: (json['warehouseName'] ?? json['warehouseShortName'] ?? '')
          .toString(),
      total: _toDouble(json['total']),
      taxes: _toDouble(json['taxes']),
      items: parseCostcoItems(
          List<Map<String, dynamic>>.from(json['itemArray'] ?? const [])),
    );
  }
}

/// Turns Costco's raw `itemArray` into basket-ready line items.
///
/// Costco prints instant savings and coupons as their own rows directly under
/// the item they discount, with a description starting with "/" (e.g.
/// "/ 1937959" or "/SNAPS") and a negative amount. Those rows are folded into
/// the nearest preceding real item, so each item's total is what was actually
/// paid. Voided rows are dropped.
List<CostcoLineItem> parseCostcoItems(List<Map<String, dynamic>> rows) {
  final items = <CostcoLineItem>[];
  for (final row in rows) {
    if (_isYes(row['voidFlag'])) continue;

    final description = [row['itemDescription01'], row['itemDescription02']]
        .where((s) => s != null && s.toString().trim().isNotEmpty)
        .map((s) => s.toString().trim())
        .join(' ');
    final amount = _toDouble(row['amount']);

    if (description.startsWith('/') && items.isNotEmpty) {
      final prev = items.removeLast();
      items.add(CostcoLineItem(
        description: prev.description,
        qty: prev.qty,
        total: _round2(prev.total + amount),
      ));
      continue;
    }

    final unit = _toDouble(row['unit']).abs().round();
    items.add(CostcoLineItem(
      description: description.isEmpty ? 'Item ${row['itemNumber'] ?? ''}' : description,
      qty: unit < 1 ? 1 : unit,
      total: _round2(amount),
    ));
  }
  return items;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

bool _isYes(dynamic v) => v == true || v?.toString().toUpperCase() == 'Y';

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Every field here is one Costco's own Orders & Purchases page requests.
/// Don't add guesses: an unknown field makes the API reject the whole query.
const costcoReceiptsQuery = r'''
query receipts($startDate: String!, $endDate: String!) {
  receipts(startDate: $startDate, endDate: $endDate) {
    warehouseName warehouseShortName transactionDateTime transactionDate
    transactionBarcode total subTotal taxes instantSavings totalItemCount
    itemArray {
      itemNumber itemDescription01 itemDescription02 unit amount
      taxFlag voidFlag
    }
  }
}''';

/// JavaScript run inside the signed-in Costco page. Reports back through the
/// `CostcoBridge` JavaScript channel as JSON: {status: 'signedOut'} |
/// {status: 'ok', receipts: [...]} | {status: 'error', message: '...'}.
String costcoFetchReceiptsJs({required int daysBack}) {
  final end = DateTime.now();
  final start = end.subtract(Duration(days: daysBack));
  String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
  final query = costcoReceiptsQuery.replaceAll(RegExp(r'\s+'), ' ');

  return '''
(async () => {
  const send = (m) => CostcoBridge.postMessage(JSON.stringify(m));
  const clientID = localStorage.getItem('clientID');
  const idToken = localStorage.getItem('idToken');
  if (!clientID || !idToken) { send({status: 'signedOut'}); return; }
  try {
    const resp = await fetch('https://ecom-api.costco.com/ebusiness/order/v1/orders/graphql', {
      method: 'POST',
      credentials: 'omit',
      headers: {
        'Content-Type': 'application/json',
        'Costco.Env': 'ecom',
        'Costco.Service': 'restOrders',
        'Costco-X-Wcs-Clientid': clientID,
        'Client-Identifier': '481b1aec-aa3b-454b-b81b-48187e28f205',
        'Costco-X-Authorization': 'Bearer ' + idToken,
      },
      body: JSON.stringify({
        query: ${jsonEncode(query)},
        variables: {startDate: '${ymd(start)}', endDate: '${ymd(end)}'},
      }),
    });
    if (resp.status === 401 || resp.status === 403) { send({status: 'signedOut'}); return; }
    if (!resp.ok) { send({status: 'error', message: 'Costco returned ' + resp.status}); return; }
    const json = await resp.json();
    if (json.errors && json.errors.length) {
      send({status: 'error', message: json.errors[0].message || 'Costco returned an error'});
      return;
    }
    send({status: 'ok', receipts: (json.data && json.data.receipts) || []});
  } catch (e) {
    send({status: 'error', message: String(e)});
  }
})();
''';
}
