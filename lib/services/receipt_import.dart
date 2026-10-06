import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../screens/receipt_review_screen.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'split_math.dart';

/// Adding a receipt to a basket, the same way whether it was scanned or came
/// from a connected store.
class ReceiptImport {
  ReceiptImport._();

  /// Lets the user review [lines], then adds the ones they keep to [basket]
  /// in one write. With [tidyNamesFor] (the store's name), receipt
  /// abbreviations are first turned into real product names. Returns how
  /// many items were added: 0 when cancelled, and null when adding failed
  /// (after telling the user).
  static Future<int?> intoBasket(
    BuildContext context,
    Basket basket, {
    required String title,
    required List<ReceiptLine> lines,
    double tax = 0,
    double? subtotal,
    String? tidyNamesFor,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (lines.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't find any items on that receipt.")));
      return 0;
    }
    final db = DatabaseService();
    final names = db.getUserNames(basket.memberIds);
    if (tidyNamesFor != null) await _tidyNames(context, lines, tidyNamesFor);
    if (!context.mounted) return 0;

    final uid = AuthService().currentUser!.uid;
    final result = await Navigator.push<ReceiptReviewResult>(
      context,
      MaterialPageRoute(
        builder: (_) => FutureBuilder<Map<String, String>>(
          future: names,
          builder: (_, snap) => ReceiptReviewScreen(
            title: title,
            lines: lines,
            memberIds: basket.memberIds,
            names: snap.data ?? const {},
            defaultPayer: uid,
            tax: tax,
            receiptSubtotal: subtotal,
          ),
        ),
      ),
    );
    if (result == null) return 0;

    final items = result.lines.map((l) {
      final qty = l.qty < 1 ? 1 : l.qty;
      final name = l.description.trim();
      return GroceryItem(
        id: const Uuid().v4(),
        name: name.isEmpty ? 'Item' : name,
        price: l.total / qty,
        quantity: qty,
        addedBy: uid,
        paidBy: result.payerId,
        userShares: evenShares(l.people),
        taxable: l.taxable,
        category: l.category,
      );
    }).toList();

    try {
      await db.addItemsToBasket(basket.id, items, receiptTax: result.tax);
      return items.length;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't add items: $e")));
      return null;
    }
  }

  /// Turns abbreviations like "KS ORG EGGS" into real product names, looking
  /// items up online when needed, and sorts them into categories. Keeps the
  /// store's names if that fails.
  static Future<void> _tidyNames(
      BuildContext context, List<ReceiptLine> lines, String store) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Flexible(child: Text('Looking up products…')),
          ],
        ),
      ),
    );
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('cleanItemNames',
              options:
                  HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call({
        'store': store,
        'items':
            lines.map((l) => {'text': l.description, 'code': l.code}).toList(),
      });
      final items = (result.data['items'] as List?) ?? const [];
      if (items.length == lines.length) {
        for (var i = 0; i < lines.length; i++) {
          final name = (items[i]['name'] ?? '').toString().trim();
          final category = items[i]['category'];
          if (name.isNotEmpty) lines[i].description = name;
          if (kItemCategories.containsKey(category)) {
            lines[i].category = category;
          }
        }
      }
    } catch (_) {
      // The store's own names still work; just less readable.
    } finally {
      if (context.mounted) Navigator.pop(context);
    }
  }

  /// Asks which basket a receipt should go in: one of the user's, or a new
  /// one (named [newName] unless they change it). Null if they back out.
  static Future<Basket?> pickBasket(BuildContext context,
      {required String newName}) async {
    final db = DatabaseService();
    final uid = AuthService().currentUser!.uid;
    final baskets = await db.getUserBaskets(uid).first;
    if (!context.mounted) return null;

    final picked = await showModalBottomSheet<Basket?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Add to which basket?',
                      style: theme.textTheme.titleLarge),
                ),
                for (final basket in baskets)
                  ListTile(
                    leading: _basketIcon(theme, Icons.shopping_basket_outlined),
                    title: Text(basket.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${basket.items.length} '
                      '${basket.items.length == 1 ? 'item' : 'items'} · '
                      '${basket.memberIds.length} '
                      '${basket.memberIds.length == 1 ? 'person' : 'people'}',
                    ),
                    onTap: () => Navigator.pop(sheet, basket),
                  ),
                ListTile(
                  leading: _basketIcon(theme, Icons.add),
                  title: const Text('New basket'),
                  subtitle: Text(newName),
                  onTap: () async {
                    final name = await _askName(sheet, newName);
                    if (name == null) return;
                    final basket = await db.createBasket(name, uid);
                    if (sheet.mounted) Navigator.pop(sheet, basket);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    return picked;
  }

  static Widget _basketIcon(ThemeData theme, IconData icon) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
      );

  static Future<String?> _askName(BuildContext context, String suggested) =>
      showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(suggested: suggested),
      );

  /// "3 items" / "1 item"
  static String itemCount(int n) => '$n ${n == 1 ? 'item' : 'items'}';
}

/// Shows that [count] items went into [basket], with a way to open it when
/// the user isn't already looking at it.
void showAddedSnack(ScaffoldMessengerState messenger, int count,
    {String? basketName, VoidCallback? open}) {
  messenger.showSnackBar(SnackBar(
    content: Text(basketName == null
        ? 'Added ${ReceiptImport.itemCount(count)}'
        : 'Added ${ReceiptImport.itemCount(count)} to $basketName'),
    action: open == null ? null : SnackBarAction(label: 'Open', onPressed: open),
  ));
}

/// Names a new basket, starting from [suggested]. Owns its text controller,
/// so it lives exactly as long as the dialog, closing animation included.
class _NameDialog extends StatefulWidget {
  final String suggested;

  const _NameDialog({required this.suggested});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.suggested);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    Navigator.pop(context, name.isEmpty ? widget.suggested : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New basket'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(onPressed: _done, child: const Text('Create')),
      ],
    );
  }
}
