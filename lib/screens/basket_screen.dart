// lib/screens/basket_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../services/auth_service.dart';
import '../services/costco_receipts.dart';
import '../services/database_service.dart';
import '../services/split_math.dart';
import '../widgets/grocery_item_tile.dart';
import 'add_item_screen.dart';
import 'basket_members_screen.dart';
import 'costco_import_screen.dart';
import 'expense_summary_screen.dart';
import 'main_screen.dart';
import 'receipt_review_screen.dart';
import 'scan_receipt_screen.dart';

class BasketScreen extends StatefulWidget {
  final String basketId;
  const BasketScreen({super.key, required this.basketId});

  @override
  State<BasketScreen> createState() => _BasketScreenState();
}

class _BasketScreenState extends State<BasketScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  int _currentIndex = 1;
  late PageController _pageController;
  // Created once: a new stream per build would re-listen to Firestore (and
  // re-download the basket) every time the screen redraws.
  late final Stream<Basket> _basketStream =
      _dbService.streamBasket(widget.basketId);

  // Names for everyone who appears in the basket, loaded once and passed down.
  Map<String, String> _names = {};
  Set<String> _namesFor = {};

  // Multi-select (long-press an item) and the "needs someone" filter.
  final Set<String> _selected = {};
  bool _onlyNeedsSomeone = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _loadNames(Basket basket) {
    final ids = {
      ...basket.memberIds,
      for (final item in basket.items) ...[item.paidBy, ...item.userShares.keys],
    };
    if (ids.length == _namesFor.length && ids.containsAll(_namesFor)) return;
    _namesFor = ids;
    _dbService.getUserNames(ids).then((names) {
      if (mounted) setState(() => _names = names);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return StreamBuilder<Basket>(
      stream: _basketStream,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          if (snapshot.hasError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => MainScreen()),
                    (route) => false,
              );
            });
          }
          return Scaffold(
            appBar: AppBar(title: Text('Basket')),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final basket = snapshot.data!;
        _loadNames(basket);
        _selected.removeWhere((id) => !basket.items.any((i) => i.id == id));

        final pages = [
          BasketMembersScreen(basket: basket),
          _basketPage(context, basket, currentUserId),
          ExpenseSummaryScreen(basket: basket),
        ];

        return Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            children: pages,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            selectedItemColor: Theme.of(context).colorScheme.secondary,
            onTap: (idx) {
              setState(() => _currentIndex = idx);
              _pageController.animateToPage(
                idx,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Members'),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Basket'),
              BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Summary'),
            ],
          ),
        );
      },
    );
  }

  /* ---------- BASKET PAGE ---------- */
  Widget _basketPage(BuildContext context, Basket basket, String uid) {
    final selecting = _selected.isNotEmpty;
    final needs = basket.items.where((i) => i.needsSomeone).length;
    final filterOn = _onlyNeedsSomeone && needs > 0;
    final visible =
        filterOn ? basket.items.where((i) => i.needsSomeone).toList() : basket.items;

    return PopScope(
      // Back leaves selection mode first.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? _selectionAppBar(basket, uid)
            : _normalAppBar(context, basket, uid),
        body: basket.items.isEmpty
            ? _emptyState(context, basket)
            : Column(
                children: [
                  _summaryBar(context, basket, uid, needs, filterOn),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: visible.length,
                      itemBuilder: (_, idx) {
                        final item = visible[idx];
                        return GroceryItemTile(
                          key: ValueKey(item.id),
                          item: item,
                          basket: basket,
                          names: _names,
                          selectionMode: selecting,
                          selected: _selected.contains(item.id),
                          onLongPress: () =>
                              setState(() => _toggleSelected(item.id)),
                          onSelectToggle: () =>
                              setState(() => _toggleSelected(item.id)),
                        );
                      },
                    ),
                  ),
                ],
              ),
        floatingActionButton: selecting
            ? null
            : FloatingActionButton(
                child: const Icon(Icons.add),
                onPressed: () => _showAddMenu(context, basket),
              ),
      ),
    );
  }

  void _toggleSelected(String id) =>
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id);

  PreferredSizeWidget _normalAppBar(BuildContext context, Basket basket, String uid) {
    final isHost = basket.hostId == uid;
    return AppBar(
      title: Text(basket.name),
      actions: [
        if (isHost)
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Finalize Basket',
            onPressed: () => _finalizeBasket(context, basket),
          ),
        PopupMenuButton<String>(
          onSelected: (action) {
            switch (action) {
              case 'allIn':
                _bulk(
                  _dbService.setOptIn(basket.id, basket.items.map((i) => i.id), uid,
                      optedIn: true),
                  "You're in on all ${basket.items.length} items",
                );
              case 'allEven':
                _confirmSplitEvenly(context, basket, basket.items.map((i) => i.id));
              case 'select':
                if (basket.items.isNotEmpty) {
                  setState(() => _selected.add(basket.items.first.id));
                }
              case 'delete':
                _deleteBasket(context, basket);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'allIn', child: Text("I'm in on everything")),
            const PopupMenuItem(value: 'allEven', child: Text('Split everything evenly')),
            const PopupMenuItem(value: 'select', child: Text('Select items')),
            if (isHost) const PopupMenuItem(value: 'delete', child: Text('Delete basket')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionAppBar(Basket basket, String uid) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Done',
        onPressed: () => setState(_selected.clear),
      ),
      title: Text('${_selected.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Select all',
          onPressed: () => setState(() => _selected.addAll(basket.items.map((i) => i.id))),
        ),
        IconButton(
          icon: const Icon(Icons.add_task),
          tooltip: "I'm in",
          onPressed: () => _bulk(
            _dbService.setOptIn(basket.id, {..._selected}, uid, optedIn: true),
            "You're in on ${_selected.length} items",
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_done),
          tooltip: "I'm out",
          onPressed: () => _bulk(
            _dbService.setOptIn(basket.id, {..._selected}, uid, optedIn: false),
            "You're out of ${_selected.length} items",
          ),
        ),
        IconButton(
          icon: const Icon(Icons.groups_outlined),
          tooltip: 'Split evenly with everyone',
          onPressed: () => _confirmSplitEvenly(context, basket, {..._selected}),
        ),
      ],
    );
  }

  Future<void> _bulk(Future<void> action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(_selected.clear);
    try {
      await action;
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't update items: $e")));
    }
  }

  Future<void> _confirmSplitEvenly(
      BuildContext context, Basket basket, Iterable<String> itemIds) async {
    final ids = itemIds.toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Split evenly?'),
        content: Text(
          'All ${basket.memberIds.length} members will split '
          '${ids.length == 1 ? 'this item' : 'these ${ids.length} items'} equally. '
          'This replaces any shares people already chose.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Split evenly')),
        ],
      ),
    );
    if (ok == true) {
      await _bulk(
        _dbService.splitEvenly(basket.id, ids, basket.memberIds),
        'Split ${ids.length} items evenly',
      );
    }
  }

  Widget _summaryBar(
      BuildContext context, Basket basket, String uid, int needs, bool filterOn) {
    final theme = Theme.of(context);
    final total = basket.items.fold(0.0, (s, i) => s + i.total);
    final mine = shareTotalFor(uid, basket.items);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Your share '),
                TextSpan(
                  text: '\$${mine.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: '  of \$${total.toStringAsFixed(2)}',
                  style: TextStyle(color: theme.hintColor),
                ),
              ]),
            ),
          ),
          if (needs > 0)
            FilterChip(
              avatar: filterOn
                  ? null
                  : Icon(Icons.filter_list, size: 18, color: Colors.deepOrange.shade400),
              label: Text('$needs need someone'),
              labelStyle: TextStyle(color: Colors.deepOrange.shade700),
              side: BorderSide(color: Colors.deepOrange.shade200),
              selected: filterOn,
              selectedColor: Colors.deepOrange.shade50,
              checkmarkColor: Colors.deepOrange.shade700,
              visualDensity: VisualDensity.compact,
              onSelected: (on) => setState(() => _onlyNeedsSomeone = on),
            )
          else
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text('All claimed', style: theme.textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, Basket basket) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_basket_outlined, size: 56, color: theme.hintColor),
            const SizedBox(height: 12),
            Text('No items yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add items by hand, scan a receipt, or import one from Costco.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add items'),
              onPressed: () => _showAddMenu(context, basket),
            ),
          ],
        ),
      ),
    );
  }

  /* ---------- PLUS BUTTON MENU ---------- */
  void _showAddMenu(BuildContext ctx, Basket basket) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add Item Manually'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => AddItemScreen(basket: basket)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Scan Receipt'),
              subtitle: const Text('Any store, from a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _scanReceipt(ctx, basket);
              },
            ),
            ListTile(
              leading: const Icon(Icons.store),
              title: const Text('Import from Costco'),
              subtitle: const Text('From your Costco account'),
              onTap: () {
                Navigator.pop(ctx);
                _importCostco(ctx, basket);
              },
            ),
          ],
        ),
      ),
    );
  }

  /* ---------- RECEIPTS ---------- */
  Future<void> _scanReceipt(BuildContext ctx, Basket basket) async {
    final receiptId = await Navigator.push<String>(
      ctx,
      MaterialPageRoute(builder: (_) => const ScanReceiptScreen()),
    );
    if (receiptId == null || !ctx.mounted) return;

    final ref = FirebaseFirestore.instance.collection('receipts').doc(receiptId);
    final data = (await ref.get()).data() ?? {};
    final docs = (await ref.collection('items').get()).docs
      ..sort((a, b) => ((a.data()['index'] ?? 0) as num)
          .compareTo((b.data()['index'] ?? 0) as num));
    if (!ctx.mounted) return;

    final lines = docs.map((d) {
      final m = d.data();
      final qty = (m['qty'] as num?)?.round() ?? 1;
      return ReceiptLine(
        description: (m['description'] ?? '').toString(),
        qty: qty < 1 ? 1 : qty,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        taxable: m['taxable'] == true,
        category: kItemCategories.containsKey(m['category']) ? m['category'] : null,
      );
    }).toList();

    final tax = (data['tax'] as num?)?.toDouble() ?? 0;
    final total = (data['total'] as num?)?.toDouble();
    final subtotal = (data['subtotal'] as num?)?.toDouble() ??
        (total != null && total > 0 ? total - tax : null);
    await _review(
      ctx,
      basket,
      title: (data['store'] as String?)?.trim().isNotEmpty == true
          ? data['store']
          : 'Scanned receipt',
      lines: lines,
      tax: tax,
      subtotal: subtotal,
    );
  }

  Future<void> _importCostco(BuildContext ctx, Basket basket) async {
    final receipt = await Navigator.push<CostcoReceipt>(
      ctx,
      MaterialPageRoute(builder: (_) => const CostcoImportScreen()),
    );
    if (receipt == null || !ctx.mounted) return;

    final lines = receipt.items
        .map((i) => ReceiptLine(
              description: i.description,
              qty: i.qty,
              total: i.total,
              taxable: i.taxable,
              code: i.itemNumber,
            ))
        .toList();
    await _tidyNames(ctx, lines, store: 'Costco');
    if (!ctx.mounted) return;

    await _review(
      ctx,
      basket,
      title: receipt.date != null
          ? 'Costco · ${DateFormat('MMM d').format(receipt.date!)}'
          : 'Costco',
      lines: lines,
      tax: receipt.taxes,
      subtotal: receipt.total > 0 ? receipt.total - receipt.taxes : null,
    );
  }

  /// Turns abbreviations like "KS ORG EGGS" into real product names, looking
  /// items up online when needed, and sorts them into categories. Keeps the
  /// original names if it fails.
  Future<void> _tidyNames(BuildContext ctx, List<ReceiptLine> lines,
      {required String store}) async {
    if (lines.isEmpty) return;
    showDialog(
      context: ctx,
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
              options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call({
        'store': store,
        'items': lines.map((l) => {'text': l.description, 'code': l.code}).toList(),
      });
      final items = (result.data['items'] as List?) ?? const [];
      if (items.length == lines.length) {
        for (var i = 0; i < lines.length; i++) {
          final name = (items[i]['name'] ?? '').toString().trim();
          final category = items[i]['category'];
          if (name.isNotEmpty) lines[i].description = name;
          if (kItemCategories.containsKey(category)) lines[i].category = category;
        }
      }
    } catch (_) {
      // Costco's own names still work; just less readable.
    } finally {
      if (ctx.mounted) Navigator.pop(ctx);
    }
  }

  /// Opens the full-screen review, then adds the chosen items in one write.
  Future<void> _review(
    BuildContext ctx,
    Basket basket, {
    required String title,
    required List<ReceiptLine> lines,
    double tax = 0,
    double? subtotal,
  }) async {
    final messenger = ScaffoldMessenger.of(ctx);
    if (lines.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't find any items on that receipt.")));
      return;
    }
    final uid = _authService.currentUser!.uid;
    final result = await Navigator.push<ReceiptReviewResult>(
      ctx,
      MaterialPageRoute(
        builder: (_) => ReceiptReviewScreen(
          title: title,
          lines: lines,
          memberIds: basket.memberIds,
          names: _names,
          defaultPayer: uid,
          tax: tax,
          receiptSubtotal: subtotal,
        ),
      ),
    );
    if (result == null) return;

    final items = result.lines.map((l) {
      final qty = l.qty < 1 ? 1 : l.qty;
      final name = l.description.trim();
      return GroceryItem(
        id: Uuid().v4(),
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
      await _dbService.addItemsToBasket(basket.id, items, receiptTax: result.tax);
      messenger.showSnackBar(SnackBar(content: Text('Added ${items.length} items')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't add items: $e")));
    }
  }

  /* ---------- FINALIZE / DELETE ---------- */
  void _finalizeBasket(BuildContext context, Basket basket) async {
    final unclaimed = basket.items.where((i) => i.needsSomeone).toList();
    final badShares = basket.items.where((i) {
      if (i.needsSomeone) return false;
      final sum = i.userShares.values
          .fold(0.0, (s, d) => s + ((d is Map ? d['share'] ?? 0 : 0) as num).toDouble());
      return (sum - 1).abs() > 0.01;
    }).toList();

    String? error;
    if (basket.items.isEmpty) {
      error = 'Add some items before finalizing.';
    } else if (unclaimed.isNotEmpty) {
      error = '${unclaimed.length == 1 ? '1 item has' : '${unclaimed.length} items have'} '
          'no one opted in yet: ${_listNames(unclaimed)}.';
    } else if (badShares.isNotEmpty) {
      error = "Shares don't add up to 100% for: ${_listNames(badShares)}.";
    }

    if (error != null) {
      final showThem = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Can't finalize yet"),
          content: Text(error!),
          actions: [
            if (unclaimed.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Show them'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
          ],
        ),
      );
      if (showThem == true) setState(() => _onlyNeedsSomeone = true);
      return;
    }

    final taxCtrl = TextEditingController(
      text: basket.receiptTax > 0 ? basket.receiptTax.toStringAsFixed(2) : '',
    );
    final taxed = basket.items.where((i) => i.taxable).toList();
    final taxedTotal = taxed.fold(0.0, (s, i) => s + i.total);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalize Basket'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: taxCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tax', prefixText: '\$'),
            ),
            const SizedBox(height: 12),
            if (basket.receiptTax > 0)
              const Text('Filled in from imported receipts. Add tax for any '
                  'items you entered by hand.\n'),
            Text(
              taxed.isEmpty
                  ? 'No items are marked as taxed, so tax is split across everything.'
                  : 'Tax is split across the ${taxed.length} taxed '
                      '${taxed.length == 1 ? 'item' : 'items'} '
                      '(\$${taxedTotal.toStringAsFixed(2)}), so nobody pays tax on '
                      'untaxed groceries.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalize')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _dbService.finalizeBasket(basket, double.tryParse(taxCtrl.text.trim()) ?? 0);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't finalize: $e")));
    }
  }

  String _listNames(List<GroceryItem> items) {
    final shown = items.take(4).map((i) => i.name).join(', ');
    return items.length > 4 ? '$shown and ${items.length - 4} more' : shown;
  }

  void _deleteBasket(BuildContext context, Basket basket) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text("Delete Basket"),
            content: Text(
                "Are you sure you want to delete this basket?\nYou won't be able to undo this"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Delete')),
            ],
          ),
    );
    if (confirm == true) await _dbService.deleteBasket(basket.id);
  }
}
