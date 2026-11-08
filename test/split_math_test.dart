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

  group('tax per trip', () {
    const costco = Trip(id: 'costco:1', store: 'Costco', date: '2026-10-03');
    const farmBoy = Trip(id: 'scan:2', store: 'Farm Boy', date: '2026-10-09');
    GroceryItem it(String id, double price,
            {Trip? trip, bool taxable = true, Map<String, dynamic>? shares}) =>
        GroceryItem(
          id: id,
          name: id,
          price: price,
          quantity: 1,
          addedBy: 'host',
          paidBy: 'host',
          userShares: shares ?? {'sam': {'share': 1.0, 'isManual': false}},
          taxable: taxable,
          trip: trip,
        );

    test("a receipt's tax stays on its own trip", () {
      final items = [
        it('tv', 100, trip: costco),
        it('oj', 10, trip: farmBoy),
      ];
      final taxes = itemTaxes(items, 0, {'costco:1': 13, 'scan:2': 1.3});
      expect(taxes[0], closeTo(13, 1e-9));
      expect(taxes[1], closeTo(1.3, 1e-9));
    });

    test('within a trip, only taxed items pay its tax', () {
      final items = [
        it('soap', 10, trip: costco),
        it('eggs', 10, trip: costco, taxable: false),
        it('oj', 10, trip: farmBoy, taxable: false),
      ];
      final taxes = itemTaxes(items, 0, {'costco:1': 1.3});
      expect(taxes, [closeTo(1.3, 1e-9), 0, 0]);
    });

    test('tax typed in by the host goes on items added by hand', () {
      final items = [it('tv', 100, trip: costco), it('gum', 2)];
      final taxes = itemTaxes(items, 0.26, {'costco:1': 13});
      expect(taxes[0], closeTo(13, 1e-9));
      expect(taxes[1], closeTo(0.26, 1e-9));
    });

    test("a deleted trip's tax isn't charged", () {
      final items = [it('oj', 10, trip: farmBoy)];
      expect(totalTax(items, 0, {'costco:1': 13, 'scan:2': 1.3}),
          closeTo(1.3, 1e-9));
    });

    test('charges and the summary agree', () {
      final items = [
        it('tv', 100, trip: costco),
        it('oj', 10, trip: farmBoy),
      ];
      const trips = {'costco:1': 13.0, 'scan:2': 1.3};
      final lines = computeCharges(items, 0, trips);
      final tax = lines.where((l) => l.isTax).fold(0.0, (s, l) => s + l.amount);
      expect(tax, closeTo(14.3, 1e-9));
      expect(taxShareFor('sam', items, 0, trips), closeTo(14.3, 1e-9));
    });
  });
}

