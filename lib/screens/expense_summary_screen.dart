import 'package:flutter/material.dart';
import '../models/basket.dart';
import '../services/auth_service.dart';
import '../services/split_math.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Who owes whom for this basket so far, worked out the same way finalizing
/// will: each item split by its shares, tax split across the taxed items.
class ExpenseSummaryScreen extends StatelessWidget {
  final Basket basket;
  final Map<String, String> names;

  const ExpenseSummaryScreen({
    super.key,
    required this.basket,
    this.names = const {},
  });

  @override
  Widget build(BuildContext context) {
    final uid = AuthService().currentUser!.uid;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final items = basket.items;
    final tax = basket.receiptTax;
    final total = items.fold(0.0, (s, i) => s + i.total);
    final myItems = shareTotalFor(uid, items);
    final myTax = taxShareFor(uid, items, tax);
    final taxedItems = items.where((i) => i.taxable).length;

    // Net with each other person: positive means they owe you.
    final net = <String, double>{};
    for (final line in computeCharges(items, tax)) {
      if (line.payeeId == uid) {
        net[line.payerId] = (net[line.payerId] ?? 0) + line.amount;
      } else if (line.payerId == uid) {
        net[line.payeeId] = (net[line.payeeId] ?? 0) - line.amount;
      }
    }
    final balances = net.entries.where((e) => e.value.abs() >= 0.005).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Summary')),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Nothing to split yet',
              message: 'Add items to the basket to see who owes what.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(context, 'Basket total', money(total + tax),
                            bold: true),
                        if (tax > 0)
                          _row(context, '${money(total)} + ${money(tax)} tax', '',
                              subtle: true),
                        const Divider(height: 24),
                        _row(context, 'Your share', money(myItems + myTax),
                            bold: true),
                        if (myTax > 0)
                          _row(context,
                              '${money(myItems)} + ${money(myTax)} tax', '',
                              subtle: true),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Balances',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (balances.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      "You're square with everyone in this basket so far.",
                      style: subtleText(context),
                    ),
                  ),
                for (final b in balances)
                  Card(
                    child: ListTile(
                      leading: PersonAvatar(name: names[b.key] ?? '…'),
                      title: Text(
                        b.value > 0
                            ? '${names[b.key] ?? '…'} owes you'
                            : 'You owe ${names[b.key] ?? '…'}',
                      ),
                      trailing: Text(
                        money(b.value.abs()),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: b.value > 0 ? colors.positive : colors.negative,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    tax > 0
                        ? 'Includes ${money(tax)} tax from imported receipts, '
                            'split across the $taxedItems taxed '
                            '${taxedItems == 1 ? 'item' : 'items'}. The host can '
                            'change the tax when finalizing.'
                        : 'Tax is added when the host finalizes the basket.',
                    style: subtleText(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false, bool subtle = false}) {
    final theme = Theme.of(context);
    final style = subtle
        ? subtleText(context)
        : (bold
            ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
            : theme.textTheme.bodyMedium);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
