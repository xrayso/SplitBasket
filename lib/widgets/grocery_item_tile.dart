import 'package:flutter/material.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../screens/edit_item_screen.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'colour-utility.dart';

/// One row in a basket. Member names come from the basket screen, which loads
/// them once, so rows never hit the database just to draw themselves.
class GroceryItemTile extends StatelessWidget {
  final GroceryItem item;
  final Basket basket;
  final Map<String, String> names;
  final bool isFinalized;

  // Multi-select: long-press a row to start, then tap rows to add/remove them.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;

  const GroceryItemTile({
    super.key,
    required this.item,
    required this.basket,
    required this.names,
    this.isFinalized = false,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onSelectToggle,
  });

  String get _uid => AuthService().currentUser?.uid ?? '';

  bool get _isOptedIn => item.shareOf(_uid) > 0.0;

  String _name(String uid) => names[uid] ?? '…';

  /// "Everyone equally", "No one yet", or "Sam 50%, Alex 50%" with manually
  /// set percentages in the theme's primary colour.
  Widget _optedInSummary(BuildContext context) {
    final theme = Theme.of(context);
    final entries = item.userShares.entries
        .where((e) => e.value is Map && ((e.value['share'] ?? 0) as num) > 0)
        .toList();

    if (entries.isEmpty) {
      return Text('No one yet', style: TextStyle(color: Colors.deepOrange.shade400));
    }

    final members = basket.memberIds.toSet();
    final everyoneEqual = entries.length == members.length &&
        entries.every((e) =>
            members.contains(e.key) &&
            (((e.value['share'] as num).toDouble()) - 1 / members.length).abs() < 1e-6);
    if (everyoneEqual && members.length > 1) {
      return Text('Everyone equally', style: TextStyle(color: Colors.green.shade600));
    }

    final spans = <TextSpan>[];
    for (final e in entries) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ', '));
      final percent = (((e.value['share'] as num).toDouble()) * 100).round();
      spans.add(TextSpan(
        text: '${_name(e.key)} $percent%',
        style: e.value['isManual'] == true
            ? TextStyle(color: theme.colorScheme.primary)
            : null,
      ));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Who paid, as a small coloured circle with their initials.
  Widget _paidByAvatar(BuildContext context) {
    final fullName = _name(item.paidBy);
    final initials = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    final baseColour = colorForName(fullName);
    return Tooltip(
      message: 'Paid by $fullName',
      child: CircleAvatar(
        radius: 13,
        backgroundColor: baseColour.withValues(alpha: 0.18),
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: onColor(baseColour, Theme.of(context).brightness),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: selected
          ? Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.10),
              theme.colorScheme.surface)
          : null,
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        onTap: selectionMode ? onSelectToggle : () => _editItem(context),
        onLongPress: isFinalized ? null : onLongPress,
        leading: selectionMode
            ? Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? theme.colorScheme.primary : null)
            : Icon(categoryIcon(item.category), color: theme.hintColor),
        minLeadingWidth: 24,
        title: Row(
          children: [
            Expanded(
              child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text('\$${item.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(child: _optedInSummary(context)),
            if (item.taxable)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('Taxed',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
              ),
          ],
        ),
        trailing: selectionMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paidByAvatar(context),
                  if (!isFinalized) ...[
                    IconButton(
                      icon: Icon(_isOptedIn
                          ? Icons.check_box
                          : Icons.check_box_outline_blank),
                      color: _isOptedIn ? Colors.green : null,
                      visualDensity: VisualDensity.compact,
                      tooltip: _isOptedIn ? 'Opt out' : 'Opt in',
                      onPressed: _toggleOptIn,
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Set percentage',
                      onPressed: () => _showShareDialog(context),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _toggleOptIn() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    // Opting out = manual share of 0; opting in = auto share of the leftover.
    await DatabaseService().setUserShare(
      basket.id,
      item,
      currentUserId: uid,
      newShare: 0.0,
      isManual: _isOptedIn,
    );
  }

  Future<void> _showShareDialog(BuildContext context) async {
    final uid = _uid;
    if (uid.isEmpty) return;

    double currentShare = item.shareOf(uid);
    final shareBeforeSlider = currentShare;
    final textCtrl = TextEditingController(
      text: (currentShare * 100).toStringAsFixed(0),
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Your share of ${item.name}'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(currentShare * 100).toStringAsFixed(0)}% · '
                    '\$${(item.total * currentShare).toStringAsFixed(2)}'),
                Slider(
                  value: currentShare,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(currentShare * 100).toStringAsFixed(0)}%',
                  onChanged: (val) {
                    setDialogState(() {
                      currentShare = val;
                      textCtrl.text = (currentShare * 100).toStringAsFixed(0);
                    });
                  },
                ),
                TextField(
                  controller: textCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Share in percent',
                    suffixText: '%',
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      setDialogState(() {
                        currentShare = parsed.clamp(0, 100) / 100.0;
                      });
                    }
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (save == true && currentShare != shareBeforeSlider) {
      await DatabaseService().setUserShare(
        basket.id,
        item,
        currentUserId: uid,
        newShare: currentShare,
        isManual: true,
      );
    }
  }

  void _editItem(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditItemScreen(basket: basket, item: item),
      ),
    );
  }
}

IconData categoryIcon(String? category) {
  switch (category) {
    case 'produce':
      return Icons.eco_outlined;
    case 'meat_seafood':
      return Icons.set_meal_outlined;
    case 'dairy_eggs':
      return Icons.egg_outlined;
    case 'bakery':
      return Icons.bakery_dining_outlined;
    case 'frozen':
      return Icons.ac_unit;
    case 'pantry':
      return Icons.kitchen_outlined;
    case 'snacks':
      return Icons.cookie_outlined;
    case 'beverages':
      return Icons.local_drink_outlined;
    case 'household':
      return Icons.cleaning_services_outlined;
    case 'personal_care':
      return Icons.spa_outlined;
    default:
      return Icons.shopping_basket_outlined;
  }
}
