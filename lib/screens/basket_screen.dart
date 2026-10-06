// lib/screens/basket_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../connectors/connections.dart';
import '../connectors/receipt_connector.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/receipt_import.dart';
import '../services/split_math.dart';
import '../theme.dart';
import '../widgets/grocery_item_tile.dart';
import '../widgets/ui.dart';
import 'add_item_screen.dart';
import 'basket_members_screen.dart';
import 'connector_screen.dart';
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
  // The add button hides while scrolling down, so it never sits on top of an
  // item's checkbox.
  bool _showAddButton = true;

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
      for (final item in basket.items) ...[
        item.paidBy,
        ...item.userShares.keys
      ],
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
          ExpenseSummaryScreen(basket: basket, names: _names),
        ];

        return Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            children: pages,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (idx) {
              setState(() => _currentIndex = idx);
              _pageController.animateToPage(
                idx,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Members',
              ),
              NavigationDestination(
                icon: Icon(Icons.shopping_cart_outlined),
                selectedIcon: Icon(Icons.shopping_cart),
                label: 'Items',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Summary',
              ),
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
    final visible = filterOn
        ? basket.items.where((i) => i.needsSomeone).toList()
        : basket.items;

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
                    child: NotificationListener<UserScrollNotification>(
                      onNotification: (n) {
                        final show = n.direction != ScrollDirection.reverse;
                        if (n.direction != ScrollDirection.idle &&
                            show != _showAddButton) {
                          setState(() => _showAddButton = show);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 4, bottom: 96),
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
                  ),
                ],
              ),
        floatingActionButton: selecting || basket.items.isEmpty
            ? null
            : AnimatedSlide(
                offset: _showAddButton ? Offset.zero : const Offset(0, 2),
                duration: const Duration(milliseconds: 200),
                child: FloatingActionButton(
                  tooltip: 'Add items',
                  onPressed: () => _showAddMenu(context, basket),
                  child: const Icon(Icons.add),
                ),
              ),
      ),
    );
  }

  void _toggleSelected(String id) =>
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id);

  PreferredSizeWidget _normalAppBar(
      BuildContext context, Basket basket, String uid) {
    final isHost = basket.hostId == uid;
    return AppBar(
      title: Text(basket.name),
      actions: [
        IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Import from a store',
          onPressed: () => _importFromStore(context, basket),
        ),
        if (isHost && basket.items.isNotEmpty)
          TextButton(
            onPressed: () => _finalizeBasket(context, basket),
            child: const Text('Finalize'),
          ),
        PopupMenuButton<String>(
          onSelected: (action) {
            switch (action) {
              case 'allIn':
                _bulk(
                  _dbService.setOptIn(
                      basket.id, basket.items.map((i) => i.id), uid,
                      optedIn: true),
                  "You're in on all ${basket.items.length} items",
                );
              case 'allEven':
                _confirmSplitEvenly(
                    context, basket, basket.items.map((i) => i.id));
              case 'select':
                if (basket.items.isNotEmpty) {
                  setState(() => _selected.add(basket.items.first.id));
                }
              case 'delete':
                _deleteBasket(context, basket);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'allIn', child: Text("I'm in on everything")),
            const PopupMenuItem(
                value: 'allEven', child: Text('Split everything evenly')),
            const PopupMenuItem(value: 'select', child: Text('Select items')),
            if (isHost)
              const PopupMenuItem(
                  value: 'delete', child: Text('Delete basket')),
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
          onPressed: () =>
              setState(() => _selected.addAll(basket.items.map((i) => i.id))),
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
      messenger
          .showSnackBar(SnackBar(content: Text("Couldn't update items: $e")));
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Split evenly')),
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

  Widget _summaryBar(BuildContext context, Basket basket, String uid, int needs,
      bool filterOn) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final total = basket.items.fold(0.0, (s, i) => s + i.total);
    final mine = shareTotalFor(uid, basket.items);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your share', style: subtleText(context)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: money(mine),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '  of ${money(total)}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          if (needs > 0)
            FilterChip(
              avatar: filterOn
                  ? null
                  : Icon(Icons.filter_list, size: 18, color: colors.warning),
              label: Text('$needs need someone'),
              labelStyle:
                  TextStyle(color: colors.warning, fontWeight: FontWeight.w600),
              side: BorderSide(color: colors.warning.withValues(alpha: 0.6)),
              selected: filterOn,
              selectedColor: colors.warning.withValues(alpha: 0.16),
              checkmarkColor: colors.warning,
              visualDensity: VisualDensity.compact,
              onSelected: (on) => setState(() {
                _onlyNeedsSomeone = on;
                _showAddButton = true;
              }),
            )
          else
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: colors.positive),
                const SizedBox(width: 4),
                Text('All claimed',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.positive, fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, Basket basket) {
    return EmptyState(
      icon: Icons.shopping_basket_outlined,
      title: 'No items yet',
      message: 'Scan a receipt, add items by hand, or import a receipt from '
          'a store you connect.',
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add items'),
            onPressed: () => _showAddMenu(context, basket),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const Text('Import'),
            onPressed: () => _importFromStore(context, basket),
          ),
        ],
      ),
    );
  }

  /* ---------- PLUS BUTTON MENU ---------- */
  void _showAddMenu(BuildContext ctx, Basket basket) {
    showModalBottomSheet(
      context: ctx,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan a receipt'),
              subtitle: const Text('Any store, from a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _scanReceipt(ctx, basket);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Add an item by hand'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                      builder: (_) => AddItemScreen(basket: basket)),
                );
              },
            ),
            const SizedBox(height: 8),
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

    final ref =
        FirebaseFirestore.instance.collection('receipts').doc(receiptId);
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
        receiptText: (m['receiptText'] ?? '').toString(),
        qty: qty < 1 ? 1 : qty,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        taxable: m['taxable'] == true,
        category:
            kItemCategories.containsKey(m['category']) ? m['category'] : null,
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    final tax = (data['tax'] as num?)?.toDouble() ?? 0;
    final total = (data['total'] as num?)?.toDouble();
    final subtotal = (data['subtotal'] as num?)?.toDouble() ??
        (total != null && total > 0 ? total - tax : null);
    final messenger = ScaffoldMessenger.of(ctx);
    final added = await ReceiptImport.intoBasket(
      ctx,
      basket,
      title: (data['store'] as String?)?.trim().isNotEmpty == true
          ? data['store']
          : 'Scanned receipt',
      lines: lines,
      tax: tax,
      subtotal: subtotal,
    );
    if (added != null && added > 0) showAddedSnack(messenger, added);
  }

  /* ---------- CONNECTED STORES ---------- */
  /// Opens a connected store's receipts, with this basket already chosen.
  Future<void> _importFromStore(BuildContext ctx, Basket basket) async {
    final connector = receiptConnectors.length == 1
        ? receiptConnectors.first
        : await showModalBottomSheet<ReceiptConnector>(
            context: ctx,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text('Import from',
                        style: Theme.of(sheet).textTheme.titleLarge),
                  ),
                  for (final c in receiptConnectors)
                    ListTile(
                      leading: Icon(c.icon),
                      title: Text(c.name),
                      subtitle: Text(c.description),
                      onTap: () => Navigator.pop(sheet, c),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
    if (connector == null || !ctx.mounted) return;
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => ConnectorScreen(connector: connector, basket: basket),
      ),
    );
  }

  /* ---------- FINALIZE / DELETE ---------- */
  void _finalizeBasket(BuildContext context, Basket basket) async {
    final unclaimed = basket.items.where((i) => i.needsSomeone).toList();
    final badShares = basket.items.where((i) {
      if (i.needsSomeone) return false;
      final sum = i.userShares.values.fold(0.0,
          (s, d) => s + ((d is Map ? d['share'] ?? 0 : 0) as num).toDouble());
      return (sum - 1).abs() > 0.01;
    }).toList();

    String? error;
    if (basket.items.isEmpty) {
      error = 'Add some items before finalizing.';
    } else if (unclaimed.isNotEmpty) {
      error =
          '${unclaimed.length == 1 ? '1 item has' : '${unclaimed.length} items have'} '
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('OK')),
          ],
        ),
      );
      if (showThem == true) {
        setState(() {
          _onlyNeedsSomeone = true;
          _showAddButton = true;
        });
      }
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Tax', prefixText: '\$'),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Finalize')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _dbService.finalizeBasket(
          basket, double.tryParse(taxCtrl.text.trim()) ?? 0);
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
      builder: (context) => AlertDialog(
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
