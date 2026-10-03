import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/charges.dart';
import '../theme.dart';
import '../widgets/colour-utility.dart';
import '../widgets/grocery_item_tile.dart' show categoryColor, categoryIcon;
import '../widgets/ui.dart';

class ChargesDetailScreen extends StatefulWidget {
  final String otherUserId;
  final String userName;
  final String currentUserId;

  const ChargesDetailScreen({super.key,
    required this.otherUserId,
    required this.userName,
    required this.currentUserId,
  });

  @override
  _ChargesDetailScreenState createState() => _ChargesDetailScreenState();
}
class _ChargesDetailScreenState extends State<ChargesDetailScreen> {
  final DatabaseService _dbService = DatabaseService();
  late final Stream<List<Charge>> _charges =
      _dbService.getChargesBetweenUsers(widget.currentUserId, widget.otherUserId);

  void _resolveCharge(Charge charge) async {
    await _dbService.resolveCharge(charge.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked as paid')),
    );
  }

  void _requestChargeResolution(Charge charge) async {
    await _dbService.requestChargeResolution(charge.id, widget.currentUserId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sent. ${widget.userName} just has to confirm.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
      ),
      body: StreamBuilder<List<Charge>>(
        stream: _charges,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final charges = snapshot.data!;
          if (charges.isEmpty) {
            return EmptyState(
              icon: Icons.celebration_outlined,
              title: "You're settled up with ${widget.userName}",
            );
          }
          charges.sort((a, b) => b.date.compareTo(a.date));

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: charges.length,
            itemBuilder: (context, index) => _chargeCard(charges[index]),
          );
        },
      ),
    );
  }

  Widget _chargeCard(Charge charge) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isPayee = widget.currentUserId == charge.payeeId;
    final isPayer = widget.currentUserId == charge.payerId;

    final sharedWith = charge.item.userShares.length;
    final detail = charge.isTax
        ? 'Tax (${(charge.item.price * 100).toStringAsFixed(1)}%)'
        : [
            if (charge.item.quantity > 1) '${charge.item.quantity} items',
            sharedWith <= 1 ? 'Not split' : 'Split $sharedWith ways',
          ].join(' · ');

    final Widget? trailing;
    if (charge.status == 'resolved') {
      trailing = Icon(Icons.check_circle, color: colors.positive);
    } else if (isPayee) {
      trailing = TextButton(
        onPressed: () => _resolveCharge(charge),
        child: Text(charge.status == 'requested' ? 'Confirm' : 'Mark paid'),
      );
    } else if (isPayer && charge.status == 'pending') {
      trailing = TextButton(
        onPressed: () => _requestChargeResolution(charge),
        child: const Text('I paid'),
      );
    } else if (isPayer && charge.status == 'requested') {
      trailing = Tooltip(
        message: 'Waiting for ${widget.userName} to confirm',
        child: Icon(Icons.hourglass_top, color: theme.colorScheme.onSurfaceVariant),
      );
    } else {
      trailing = null;
    }

    final category = charge.isTax ? null : charge.item.category;
    final colour = charge.isTax ? theme.colorScheme.outline : categoryColor(category);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colour.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.24 : 0.13),
                  theme.colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                charge.isTax ? Icons.percent : categoryIcon(category),
                size: 22,
                color: onColor(colour, theme.brightness),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(charge.isTax ? 'Tax' : charge.item.name,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  Text('$detail · ${DateFormat('MMM d').format(charge.date)}',
                      style: subtleText(context)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              money(charge.amount),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isPayee ? colors.positive : colors.negative,
              ),
            ),
            if (trailing != null) trailing else const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
