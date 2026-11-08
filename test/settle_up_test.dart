import 'package:flutter_test/flutter_test.dart';
import 'package:split_basket/models/charges.dart';
import 'package:split_basket/models/grocery_item.dart';
import 'package:split_basket/services/settle_up.dart';

var _n = 0;
Charge charge(String payer, String payee, double amount,
        {String status = 'pending', String requestedBy = ''}) =>
    Charge(
      id: 'c${_n++}',
      payerId: payer,
      payeeId: payee,
      amount: amount,
      item: GroceryItem(
          id: 'i',
          name: 'x',
          price: amount,
          quantity: 1,
          addedBy: payee,
          paidBy: payee,
          userShares: const {}),
      date: DateTime(2026, 11, 1),
      isTax: false,
      status: status,
      requestedBy: requestedBy,
    );

void main() {
  test('balances net out both ways', () {
    // I owe Sam $15, Sam owes me $20: Sam owes me $5.
    final b = netBalances([charge('me', 'sam', 15), charge('sam', 'me', 20)], 'me');
    expect(b.single.otherUserId, 'sam');
    expect(b.single.netAmount, closeTo(-5, 1e-9));
  });

  test("I'm waiting once all I owe is marked paid, whatever they owe me", () {
    final b = netBalances([
      charge('me', 'sam', 20, status: 'requested', requestedBy: 'me'),
      charge('sam', 'me', 15),
    ], 'me');
    expect(b.single.netAmount, closeTo(5, 1e-9));
    expect(b.single.requested, isTrue);
  });

  test('not waiting while some of what I owe is still unpaid', () {
    final b = netBalances([
      charge('me', 'sam', 20, status: 'requested', requestedBy: 'me'),
      charge('me', 'sam', 3),
    ], 'me');
    expect(b.single.requested, isFalse);
  });

  test('a payment claim shows the net, not their side alone', () {
    // Sam owes me $20 and I owe Sam $15; Sam pays $5 and says so.
    final claims = paymentClaims([
      charge('sam', 'me', 20, status: 'requested', requestedBy: 'sam'),
      charge('me', 'sam', 15),
    ], 'me');
    expect(claims.single.requestedBy, 'sam');
    expect(claims.single.totalAmountRequested, closeTo(5, 1e-9));
  });

  test('one claim per person, however many charges', () {
    final claims = paymentClaims([
      charge('sam', 'me', 4, status: 'requested', requestedBy: 'sam'),
      charge('sam', 'me', 6, status: 'requested', requestedBy: 'sam'),
      charge('alex', 'me', 2),
    ], 'me');
    expect(claims.length, 1);
    expect(claims.single.totalAmountRequested, closeTo(10, 1e-9));
    expect(claims.single.chargeIds.length, 2);
  });
}
