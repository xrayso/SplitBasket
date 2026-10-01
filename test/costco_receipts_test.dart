import 'package:flutter_test/flutter_test.dart';
import 'package:split_basket/services/costco_receipts.dart';

void main() {
  test('folds instant savings and coupons into the item above them', () {
    final items = parseCostcoItems([
      {'itemNumber': '5551212', 'itemDescription01': 'KS SNACK MIX', 'unit': 1, 'amount': 19.98},
      {'itemNumber': '5551212', 'itemDescription01': '/ 5551212', 'unit': -1, 'amount': -3.00},
      {'itemNumber': '5551212', 'itemDescription01': '/SNAPS', 'amount': -2.00},
      {'itemNumber': '1937959', 'itemDescription01': 'NIGHT LIGHT', 'itemDescription02': '3PK P216', 'unit': 2, 'amount': '23.99'},
    ]);

    expect(items.map((i) => i.description), ['KS SNACK MIX', 'NIGHT LIGHT 3PK P216']);
    expect(items[0].total, 14.98);
    expect(items[0].qty, 1);
    expect(items[1].total, 23.99);
    expect(items[1].qty, 2);
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
