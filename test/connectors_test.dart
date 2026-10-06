import 'package:flutter_test/flutter_test.dart';
import 'package:split_basket/connectors/connections.dart';
import 'package:split_basket/connectors/costco_connector.dart';

void main() {
  const costco = CostcoConnector();

  test('every connector has its own id', () {
    final ids = receiptConnectors.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('Costco reads its own pages only', () {
    expect(costco.isStorePage(Uri.parse('https://www.costco.ca/OrderStatusCmd')),
        isTrue);
    expect(costco.isStorePage(Uri.parse('https://costco.ca/')), isTrue);
    expect(costco.isStorePage(Uri.parse('https://notcostco.ca/')), isFalse);
    expect(costco.isStorePage(Uri.parse('https://signin.costco.com/')), isFalse);
  });

  test('a Costco receipt becomes basket lines, discounts folded in', () {
    final receipt = costco.parseReceipt({
      'transactionBarcode': '21134300501862310021',
      'transactionDateTime': '2026-10-03T14:21:00',
      'warehouseName': 'KINGSTON',
      'total': 30.5,
      'taxes': 1.5,
      'itemArray': [
        {'itemNumber': '1937959', 'itemDescription01': 'LUBRIDERM',
          'unit': 1, 'amount': 14.99, 'taxFlag': 'Y'},
        {'itemNumber': '', 'itemDescription01': 'TPD/1937959',
          'unit': -1, 'amount': -4, 'taxFlag': 'Y'},
        {'itemNumber': '27003', 'itemDescription01': 'ORG SPINACH',
          'unit': 1, 'amount': 4.99, 'taxFlag': 'N'},
      ],
    });

    expect(receipt.id, '21134300501862310021');
    expect(receipt.title, 'Costco · Oct 3');
    expect(receipt.place, 'Kingston');
    expect(receipt.itemCount, 2);
    expect(receipt.subtotal, 29.0);

    final lines = receipt.lines();
    expect(lines.map((l) => l.description), ['LUBRIDERM', 'ORG SPINACH']);
    expect(lines.first.total, closeTo(10.99, 0.001));
    expect(lines.first.discount, 4);
    expect(lines.first.taxable, isTrue);
    expect(lines.first.code, '1937959');
    expect(lines.last.taxable, isFalse);

    // Each import edits its own copy.
    lines.first.description = 'Lubriderm Lotion';
    expect(receipt.lines().first.description, 'LUBRIDERM');
  });
}
