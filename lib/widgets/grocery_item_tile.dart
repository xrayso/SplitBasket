import 'package:flutter/material.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../screens/edit_item_screen.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'colour-utility.dart';
import 'ui.dart';

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
  /// set percentages in the theme's primary colour, plus "Taxed".
  Widget _sharesLine(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final base = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final entries = item.userShares.entries
        .where((e) => e.value is Map && ((e.value['share'] ?? 0) as num) > 0)
        .toList();

    final spans = <InlineSpan>[];
    if (entries.isEmpty) {
      spans.add(TextSpan(
        text: 'No one yet',
        style: TextStyle(color: colors.warning, fontWeight: FontWeight.w600),
      ));
    } else {
      final members = basket.memberIds.toSet();
      final everyoneEqual = members.length > 1 &&
          entries.length == members.length &&
          entries.every((e) =>
              members.contains(e.key) &&
              (((e.value['share'] as num).toDouble()) - 1 / members.length)
                      .abs() <
                  1e-6);
      if (everyoneEqual) {
        spans.add(TextSpan(
          text: 'Everyone equally',
          style: TextStyle(color: colors.positive, fontWeight: FontWeight.w500),
        ));
      } else {
        for (final e in entries) {
          if (spans.isNotEmpty) spans.add(const TextSpan(text: ', '));
          final percent =
              (((e.value['share'] as num).toDouble()) * 100).round();
          spans.add(TextSpan(
            text: '${_name(e.key)} $percent%',
            style: e.value['isManual'] == true
                ? TextStyle(color: theme.colorScheme.primary)
                : null,
          ));
        }
      }
    }
    if (item.taxable) spans.add(const TextSpan(text: ' · Taxed'));

    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// The item's category as a small tinted tile (or a selection circle while
  /// selecting items).
  Widget _leading(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (selectionMode) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? scheme.primary : scheme.outline,
          size: 26,
        ),
      );
    }
    final colour = categoryColor(item.category);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            colour.withValues(alpha: dark ? 0.24 : 0.13), scheme.surface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(categoryIcon(item.category),
          size: 22, color: onColor(colour, theme.brightness)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payer = _name(item.paidBy);
    return Card(
      color: selected
          ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.14),
              scheme.surfaceContainerLow)
          : null,
      child: InkWell(
        onTap: selectionMode ? onSelectToggle : () => _editItem(context),
        onLongPress: isFinalized ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _leading(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name gets the full width; the price sits beside it.
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500, height: 1.25),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(item.total),
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (item.quantity > 1)
                                Text('${item.quantity} × ${money(item.price)}',
                                    style: subtleText(context)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(child: _sharesLine(context)),
                        Tooltip(
                          message: 'Paid by $payer',
                          child: PersonAvatar(name: payer, radius: 12),
                        ),
                        if (!isFinalized && !selectionMode) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(_isOptedIn
                                ? Icons.check_box
                                : Icons.check_box_outline_blank),
                            color: _isOptedIn ? scheme.primary : scheme.outline,
                            visualDensity: VisualDensity.compact,
                            tooltip: _isOptedIn ? "I'm out" : "I'm in",
                            onPressed: _toggleOptIn,
                          ),
                          IconButton(
                            icon: const Icon(Icons.tune, size: 20),
                            color: scheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Set my share',
                            onPressed: () => _showShareDialog(context),
                          ),
                        ] else
                          const SizedBox(width: 12, height: 40),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
        title: const Text('Your share'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtleText(context)),
                const SizedBox(height: 16),
                Text(
                  '${(currentShare * 100).toStringAsFixed(0)}% · '
                  '${money(item.total * currentShare)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
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

/// A colour per category, for the item's icon tile.
Color categoryColor(String? category) {
  switch (category) {
    case 'produce':
      return const Color(0xFF43A047);
    case 'meat_seafood':
      return const Color(0xFFE53935);
    case 'dairy_eggs':
      return const Color(0xFF1E88E5);
    case 'bakery':
      return const Color(0xFFFB8C00);
    case 'frozen':
      return const Color(0xFF00ACC1);
    case 'pantry':
      return const Color(0xFF8D6E63);
    case 'snacks':
      return const Color(0xFF8E24AA);
    case 'beverages':
      return const Color(0xFF3949AB);
    case 'household':
      return const Color(0xFF00897B);
    case 'personal_care':
      return const Color(0xFFD81B60);
    default:
      return const Color(0xFF78909C);
  }
}
