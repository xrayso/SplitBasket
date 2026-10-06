// Costco warehouse receipts, read from the same (undocumented) GraphQL API
// that the "Orders & Purchases" page on costco.ca / costco.com uses.
//
// The request runs *inside* the signed-in Costco web page (see
// CostcoConnector and ConnectorScreen), so the user's Costco password and
// tokens never leave that page — nothing is sent to Firebase.

import 'dart:convert';

class CostcoLineItem {
  final String description;
  final int qty;
  final double total; // net of instant savings / coupons
  final double discount; // instant savings / coupons taken off, as a positive amount
  final bool taxable;
  final String itemNumber; // lets the name lookup search Costco's catalogue

  CostcoLineItem({
    required this.description,
    required this.qty,
    required this.total,
    this.discount = 0,
    this.taxable = false,
    this.itemNumber = '',
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
/// Costco prints instant savings and coupons as their own rows with a
/// negative amount and a description that points at the item they discount,
/// either by item number ("TPD/1937959", "/ 1937959") or by name
/// ("/AAA BATTERY"). Each of those rows is folded into the item it points at
/// (or the item above it, when the reference matches nothing), so an item's
/// total is what was actually paid for it. Voided rows are dropped.
List<CostcoLineItem> parseCostcoItems(List<Map<String, dynamic>> rows) {
  final items = <_Draft>[];
  final discounts = <({String? ref, double amount, int above, String text})>[];

  for (final row in rows) {
    if (_isYes(row['voidFlag'])) continue;

    final description = [row['itemDescription01'], row['itemDescription02']]
        .where((s) => s != null && s.toString().trim().isNotEmpty)
        .map((s) => s.toString().trim())
        .join(' ');
    final amount = _toDouble(row['amount']);

    final ref = amount < 0 ? _discountRef(description) : null;
    if (ref != null) {
      discounts.add((
        ref: ref.isEmpty ? null : ref,
        amount: amount,
        above: items.length - 1,
        text: description,
      ));
      continue;
    }

    final unit = _toDouble(row['unit']).abs().round();
    items.add(_Draft(
      description: description.isEmpty ? 'Item ${row['itemNumber'] ?? ''}' : description,
      qty: unit < 1 ? 1 : unit,
      total: amount,
      taxable: _isTaxed(row['taxFlag']),
      itemNumber: row['itemNumber']?.toString().trim() ?? '',
    ));
  }

  final loose = <_Draft>[];
  for (final d in discounts) {
    final parent = _findDiscounted(items, d.ref, d.above);
    if (parent == null) {
      // Nothing to attach it to (e.g. an order-wide coupon): keep it as a line.
      loose.add(_Draft(description: d.text, qty: 1, total: d.amount));
    } else {
      parent.total += d.amount;
      parent.discount -= d.amount;
    }
  }

  return [...items, ...loose]
      .map((d) => CostcoLineItem(
            description: d.description,
            qty: d.qty,
            total: _round2(d.total),
            discount: _round2(d.discount),
            taxable: d.taxable,
            itemNumber: d.itemNumber,
          ))
      .toList();
}

class _Draft {
  final String description;
  final int qty;
  double total;
  double discount = 0;
  final bool taxable;
  final String itemNumber;

  _Draft({
    required this.description,
    required this.qty,
    required this.total,
    this.taxable = false,
    this.itemNumber = '',
  });
}

/// For a negative row, what it says it discounts: the text after the "/" in
/// "TPD/1937959" or "/AAA BATTERY", '' for a discount that names nothing
/// ("INSTANT SAVINGS"), or null when the row isn't a discount at all (e.g. a
/// returned item, which keeps its own line).
String? _discountRef(String description) {
  final slash = description.lastIndexOf('/');
  if (slash >= 0) return description.substring(slash + 1).trim();
  final d = description.toUpperCase();
  if (d.isEmpty ||
      RegExp(r'^(TPD|INST(ANT)?\.? ?SAV|SAVINGS|COUPON|CPN|MFR|MCP|DISC)')
          .hasMatch(d)) {
    return '';
  }
  return null;
}

/// The item a discount belongs to: matched by item number, then by name, then
/// the item printed right above the discount.
_Draft? _findDiscounted(List<_Draft> items, String? ref, int above) {
  if (ref != null) {
    final digits = RegExp(r'^\d+$').hasMatch(ref);
    if (digits) {
      final number = int.parse(ref);
      final byNumber = items.where((i) => int.tryParse(i.itemNumber) == number);
      if (byNumber.isNotEmpty) return byNumber.first;
    } else {
      final r = ref.toUpperCase();
      for (final i in items) {
        if (i.description.toUpperCase() == r) return i;
      }
      for (final i in items) {
        final desc = i.description.toUpperCase();
        if (desc.contains(r) || (r.contains(desc) && desc.length * 2 >= r.length)) {
          return i;
        }
      }
      final words = r.split(RegExp(r'\s+')).where((w) => w.length >= 3).toSet();
      _Draft? best;
      var bestScore = 0;
      for (final i in items) {
        final score = i.description
            .toUpperCase()
            .split(RegExp(r'\s+'))
            .where(words.contains)
            .length;
        if (score > bestScore) (best, bestScore) = (i, score);
      }
      if (best != null) return best;
    }
  }
  return above >= 0 ? items[above] : null;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

bool _isYes(dynamic v) => v == true || v?.toString().toUpperCase() == 'Y';

/// Costco marks taxed items with a flag that may come back as a bool, "Y"/"N",
/// or a tax-code letter; anything but empty/"N"/false counts as taxed.
bool _isTaxed(dynamic v) {
  if (v is bool) return v;
  final s = v?.toString().trim().toUpperCase() ?? '';
  return s.isNotEmpty && !const {'N', '0', 'FALSE', 'NO'}.contains(s);
}

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
/// `ReceiptBridge` JavaScript channel as JSON: {status: 'signedOut'} |
/// {status: 'ok', receipts: [...]} | {status: 'error', message: '...'}.
String costcoFetchReceiptsJs({required int daysBack}) {
  final end = DateTime.now();
  final start = end.subtract(Duration(days: daysBack));
  String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
  final query = costcoReceiptsQuery.replaceAll(RegExp(r'\s+'), ' ');

  return '''
(async () => {
  const send = (m) => ReceiptBridge.postMessage(JSON.stringify(m));
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
