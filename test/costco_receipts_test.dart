import 'package:flutter_test/flutter_test.dart';
import 'package:split_basket/services/costco_receipts.dart';

void main() {
  test('folds instant savings and coupons into the item above them', () {
    final items = parseCostcoItems([
      {'itemNumber': '5551212', 'itemDescription01': 'KS SNACK MIX', 'unit': 1, 'amount': 19.98},
      {'itemNumber': '345678', 'itemDescription01': '/ 5551212', 'unit': -1, 'amount': -3.00},
      {'itemNumber': '5551212', 'itemDescription01': '/SNAPS', 'amount': -2.00},
      {'itemNumber': '1937959', 'itemDescription01': 'NIGHT LIGHT', 'itemDescription02': '3PK P216', 'unit': 2, 'amount': '23.99'},
    ]);

    expect(items.map((i) => i.description), ['KS SNACK MIX', 'NIGHT LIGHT 3PK P216']);
    expect(items[0].total, 14.98);
    expect(items[0].discount, 5.00);
    expect(items[0].qty, 1);
    expect(items[1].total, 23.99);
    expect(items[1].discount, 0);
    expect(items[1].qty, 2);
  });

  test('folds TPD discounts into the item they name, wherever they are', () {
    // As costco.ca sends them: "TPD/<item number>" with a negative amount.
    final items = parseCostcoItems([
      {'itemNumber': '1234567', 'itemDescription01': 'LUBRIDERM', 'unit': 1, 'amount': 14.99, 'taxFlag': 'Y'},
      {'itemNumber': '7654321', 'itemDescription01': 'ORG SPINACH', 'unit': 1, 'amount': 4.99, 'taxFlag': 'N'},
      {'itemNumber': '345678', 'itemDescription01': 'TPD/1234567', 'unit': -1, 'amount': -4.00},
      {'itemNumber': '1111111', 'itemDescription01': 'ORAL-B BRUSH', 'unit': 1, 'amount': 16.99, 'taxFlag': 'Y'},
      {'itemNumber': '345679', 'itemDescription01': 'TPD/1111111', 'unit': -1, 'amount': -4.00},
    ]);

    expect(items.map((i) => i.description), ['LUBRIDERM', 'ORG SPINACH', 'ORAL-B BRUSH']);
    expect(items.map((i) => i.total), [10.99, 4.99, 12.99]);
    expect(items.map((i) => i.discount), [4.00, 0, 4.00]);
    expect(items.map((i) => i.taxable), [true, false, true]);
  });

  test('matches a discount by name, or the item above when nothing matches', () {
    final items = parseCostcoItems([
      {'itemNumber': '379938', 'itemDescription01': 'DURACELL AAA', 'amount': 14.99},
      {'itemNumber': '1', 'itemDescription01': 'BANANAS', 'amount': 1.99},
      {'itemNumber': '2', 'itemDescription01': '/AAA BATTERY', 'unit': -1, 'amount': -2.50},
      {'itemNumber': '3', 'itemDescription01': 'TPD/9999999', 'unit': -1, 'amount': -0.50},
    ]);

    expect(items.map((i) => i.total), [12.49, 1.49]);
  });

  test('keeps returns and orphaned coupons as their own lines', () {
    final items = parseCostcoItems([
      {'itemNumber': '2', 'itemDescription01': 'INSTANT SAVINGS', 'amount': -5.00},
      {'itemNumber': '1', 'itemDescription01': 'KS EGGS', 'unit': 1, 'amount': 9.49},
      {'itemNumber': '3', 'itemDescription01': 'PAPER TOWEL', 'unit': -1, 'amount': -24.99},
    ]);

    expect(items.map((i) => i.description), ['KS EGGS', 'PAPER TOWEL', 'INSTANT SAVINGS']);
    expect(items.map((i) => i.total), [9.49, -24.99, -5.00]);
  });

  test('keeps the tax flag, including on items with discounts', () {
    final items = parseCostcoItems([
      {'itemDescription01': 'PAPER TOWEL', 'amount': 24.99, 'taxFlag': 'Y'},
      {'itemDescription01': '/ 1234567', 'amount': -4.00, 'taxFlag': 'N'},
      {'itemDescription01': 'BANANAS', 'amount': 1.99, 'taxFlag': 'N'},
      {'itemDescription01': 'SOAP', 'amount': 9.99, 'taxFlag': true},
      {'itemDescription01': 'MILK', 'amount': 6.49},
    ]);
    expect(items.map((i) => i.taxable), [true, false, true, false]);
    expect(items[0].total, 20.99);
  });

  test('drops voided rows and defaults missing quantity to 1', () {
    final items = parseCostcoItems([
      {'itemDescription01': 'ROTISSERIE CHKN', 'amount': 7.99},
      {'itemDescription01': 'KS ORG EGGS', 'amount': 9.49, 'voidFlag': 'Y'},
    ]);

    expect(items, hasLength(1));
    expect(items.single.description, 'ROTISSERIE CHKN');
    expect(items.single.qty, 1);
  });

  test('reads receipt-level fields', () {
    final receipt = CostcoReceipt.fromJson({
      'transactionBarcode': '21134300501862509141413',
      'transactionDateTime': '2025-09-14T14:13:00',
      'warehouseName': 'OTTAWA SOUTH',
      'total': 52.41,
      'taxes': 1.23,
      'itemArray': [
        {'itemDescription01': 'BANANAS', 'unit': 1, 'amount': 1.99},
      ],
    });

    expect(receipt.date, DateTime(2025, 9, 14, 14, 13));
    expect(receipt.warehouse, 'OTTAWA SOUTH');
    expect(receipt.total, 52.41);
    expect(receipt.taxes, 1.23);
    expect(receipt.items.single.description, 'BANANAS');
  });
}
