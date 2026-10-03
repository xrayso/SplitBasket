import 'package:flutter_test/flutter_test.dart';
import 'package:split_basket/models/grocery_item.dart';
import 'package:split_basket/services/split_math.dart';

GroceryItem item(String name, double price, Map<String, dynamic> shares,
        {bool taxable = false, String paidBy = 'host', int qty = 1}) =>
    GroceryItem(
      id: name,
      name: name,
      price: price,
      quantity: qty,
      addedBy: 'host',
      paidBy: paidBy,
      userShares: shares,
      taxable: taxable,
    );

double owedBy(List<ChargeLine> lines, String uid, {bool tax = false}) => lines
    .where((l) => l.payerId == uid && l.isTax == tax)
    .fold(0.0, (s, l) => s + l.amount);

void main() {
  group('shares', () {
    test('opting in splits the leftover between auto users', () {
      var s = withOptIn({}, 'a');
      s = withOptIn(s, 'b');
      expect(s['a']['share'], 0.5);
      expect(s['b']['share'], 0.5);
    });

    test('manual shares are kept and the rest is split', () {
      var s = withShare({}, 'a', share: 0.7, isManual: true);
      s = withOptIn(s, 'b');
      s = withOptIn(s, 'c');
      expect(s['a']['share'], 0.7);
      expect(s['b']['share'], closeTo(0.15, 1e-9));
      // Opting in again doesn't wipe a manual share.
      s = withOptIn(s, 'a');
      expect(s['a']['share'], 0.7);
    });

    test('opting out removes the user and rebalances', () {
      var s = evenShares(['a', 'b', 'c']);
      s = withOptOut(s, 'c');
      expect(s.containsKey('c'), isFalse);
      expect(s['a']['share'], 0.5);
    });
  });

  group('charges', () {
    test('tax only lands on people who shared taxable items', () {
      final items = [
        // Bananas aren't taxed; only Sam shares them with the host.
        item('Bananas', 10, evenShares(['host', 'sam'])),
        // Paper towels are taxed; only Alex shares them with the host.
        item('Paper towels', 20, evenShares(['host', 'alex']), taxable: true),
      ];
      final lines = computeCharges(items, 2.60); // 13% of $20

      expect(owedBy(lines, 'sam'), 5.0);
      expect(owedBy(lines, 'sam', tax: true), 0.0);
      expect(owedBy(lines, 'alex'), 10.0);
      expect(owedBy(lines, 'alex', tax: true), closeTo(1.30, 1e-9));
      final alexTax = lines.firstWhere((l) => l.payerId == 'alex' && l.isTax);
      expect(alexTax.taxRate, closeTo(0.13, 1e-9));
    });

    test('with nothing marked taxable, tax is spread across everything', () {
      final items = [
        item('Bananas', 10, evenShares(['host', 'sam'])),
        item('Paper towels', 30, evenShares(['host', 'alex'])),
      ];
      final lines = computeCharges(items, 4.0); // 10% of the $40 total

      expect(owedBy(lines, 'sam', tax: true), closeTo(0.5, 1e-9));
      expect(owedBy(lines, 'alex', tax: true), closeTo(1.5, 1e-9));
    });

    test("the payer isn't charged for their own share", () {
      final lines = computeCharges(
          [item('Eggs', 8, evenShares(['host', 'sam']), taxable: true)], 1.0);
      expect(lines.where((l) => l.payerId == 'host'), isEmpty);
      expect(owedBy(lines, 'sam'), 4.0);
      expect(owedBy(lines, 'sam', tax: true), 0.5);
    });

    test('quantity counts toward cost and tax', () {
      final lines = computeCharges(
          [item('Soda', 2, evenShares(['host', 'sam']), qty: 6, taxable: true)],
          1.56);
      expect(owedBy(lines, 'sam'), 6.0);
      expect(owedBy(lines, 'sam', tax: true), closeTo(0.78, 1e-9));
    });
  });

  test('needsSomeone and shareTotalFor', () {
    final items = [
      item('Milk', 6, evenShares(['host', 'sam'])),
      item('Chips', 4, {}),
    ];
    expect(items[0].needsSomeone, isFalse);
    expect(items[1].needsSomeone, isTrue);
    expect(shareTotalFor('sam', items), 3.0);
  });

  test('taxShareFor matches what finalizing charges', () {
    final items = [
      item('Soap', 10, evenShares(['host', 'sam']), taxable: true),
      item('Lotion', 30, {'host': {'share': 0.25, 'isManual': true},
          'sam': {'share': 0.75, 'isManual': false}}, taxable: true),
      item('Spinach', 5, evenShares(['host', 'sam'])),
    ];
    // $4 of tax on $40 of taxed items: soap carries $1, lotion $3.
    expect(taxShareFor('host', items, 4.0), closeTo(0.5 + 0.75, 1e-9));
    expect(taxShareFor('sam', items, 4.0), closeTo(0.5 + 2.25, 1e-9));
    expect(taxShareFor('sam', items, 4.0),
        closeTo(owedBy(computeCharges(items, 4.0), 'sam', tax: true), 1e-9));
    expect(taxShareFor('sam', items, 0), 0);
  });
}
