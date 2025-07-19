// lib/screens/basket_screen.dart
// UPDATED: adds “Scan Receipt” flow to the ➕ button.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/grocery_item_tile.dart';
import 'add_item_screen.dart';
import 'basket_members_screen.dart';
import 'expense_summary_screen.dart';
import 'main_screen.dart';
import 'scan_receipt_screen.dart';          // ⬅ NEW IMPORT

class BasketScreen extends StatefulWidget {
  final String basketId;
  const BasketScreen({super.key, required this.basketId});

  @override
  _BasketScreenState createState() => _BasketScreenState();
}

class _BasketScreenState extends State<BasketScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  int _currentIndex = 1;
  late PageController _pageController;

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

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return StreamBuilder<Basket>(
      stream: _dbService.streamBasket(widget.basketId),
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
        final pages = [
          BasketMembersScreen(basket: basket),
          Scaffold(
            appBar: AppBar(
              title: Text(basket.name),
              actions: [
                if (basket.hostId == currentUserId)
                  IconButton(
                    icon: const Icon(Icons.check),
                    tooltip: 'Finalize Basket',
                    onPressed: () => _finalizeBasket(context, basket),
                  ),
                if (basket.hostId == currentUserId)
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete Basket',
                    onPressed: () => _deleteBasket(context, basket),
                  ),
              ],
            ),
            body: basket.items.isEmpty
                ? const Center(child: Text('No items added yet.'))
                : ListView.builder(
              itemCount: basket.items.length,
              itemBuilder: (_, idx) => GroceryItemTile(
                key: ValueKey(basket.items[idx].id),
                item: basket.items[idx],
                basketId: widget.basketId,
              ),
            ),
            floatingActionButton: FloatingActionButton(
              child: const Icon(Icons.add),
              onPressed: () => _showAddMenu(context, basket),
            ),
          ),
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
              onTap: () async {
                Navigator.pop(ctx);
                final receiptId = await Navigator.push<String>(
                  ctx,
                  MaterialPageRoute(builder: (_) => const ScanReceiptScreen()),
                );
                if (receiptId != null) {
                  // Pull parsed line-items and add to basket
                  final snap = await FirebaseFirestore.instance
                      .collection('receipts/$receiptId/items')
                      .get();

                  final result = await _showReceiptPreviewDialog(
                    ctx,
                    snap.docs,
                    basket.memberIds,
                    _authService.currentUser!.uid,
                  );

                  if (result == null) return; // user cancelled

                  for (final it in result.items.where((i) => i.include)) {
                    await _dbService.addItemToBasket(
                      basket.id,
                      GroceryItem(
                        id: Uuid().v4(),
                        name: it.description,
                        price: it.total / it.qty,
                        quantity: it.qty,
                        addedBy: _authService.currentUser!.uid,
                        paidBy: result.selectedPayer,
                        userShares: {},
                      ),
                    );
                  }
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Added ${result.items.where((i)=>i.include).length} items!'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _finalizeBasket(BuildContext context, Basket basket) async {
    String finalizeError = "";
    String itemNotOptedIn = "";
    String itemNotCorrectShare = "";
    for (GroceryItem item in basket.items){
      double shareSum = 0;
      if (item.userShares.isEmpty){
        itemNotOptedIn = item.name;
        break;
      }
      for (Map<String, dynamic> shareInfo in item.userShares.values){
        shareSum += shareInfo['share'];
      }
      if (shareSum - 1 > 0.01 || shareSum - 1 < -0.01){
        itemNotCorrectShare = item.name;
        break;
      }
    }

    if (basket.items.isEmpty){
      finalizeError = "You cannot finalize a basket with no items. Please add items to the basket before finalizing";
    }else if (itemNotOptedIn != ""){
      finalizeError = "No one has opted into item [$itemNotOptedIn]}.";
    }else if (itemNotCorrectShare != ""){
      finalizeError = "Shares do not add up to cost for item [$itemNotCorrectShare].";
    }


    if (finalizeError != "") {
      await showDialog(
        context: context,
        builder: (context) =>
            AlertDialog(
              title: Text('Cannot Finalize Basket'),
              content: Text(finalizeError),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK'),
                )
              ],
            ),
      );
      return;
    }

    final textCtrl = TextEditingController(
      text: (0).toStringAsFixed(0),
    );
    double taxPercent = 0;
    double totalBasketCost = await _dbService.calculateTotalBasketPrice(basket.id);
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Finalize Basket'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Enter Tax Cost (\$)',
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      setDialogState(() {
                        taxPercent = parsed / totalBasketCost;
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
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Finalize')),
            ],
          ),
    );
    if (confirm) await _dbService.finalizeBasket(basket, taxPercent);
  }

  void _deleteBasket(BuildContext context, Basket basket) async {
    bool confirm = await showDialog(
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
    if (confirm) await _dbService.deleteBasket(basket.id);
  }
  /// Shows the preview & returns null if cancelled,
  /// or a ReceiptPreviewResult with the edited items & payer.
  Future<ReceiptPreviewResult?> _showReceiptPreviewDialog(
      BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      List<String> possiblePayers,
      String defaultPayer,
      ) async {
    // convert docs → UI items
    final previewItems = docs.map((d) {
      return _ReceiptPreviewItem(
        description: d['description'] as String,
        qty: (d['qty'] as num).toInt(),
        total: (d['total'] as num).toDouble(),
      );
    }).toList();
    Map<String, String> userIdToName = {};
    for (String id in possiblePayers){
      userIdToName[id] = await _dbService.getUserNameById(id);
    }
    String selectedPayer = defaultPayer;
    return showDialog<ReceiptPreviewResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('Preview Receipt Items'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Global payer selector
                DropdownButtonFormField<String>(
                  value: selectedPayer,
                  decoration: const InputDecoration(labelText: 'Who paid?'),
                  items: possiblePayers
                      .map((u) => DropdownMenuItem(value: u, child: Text(userIdToName[u]!)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedPayer = v!),
                ),
                const SizedBox(height: 12),

                // Editable, toggleable list
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: previewItems.length,
                    itemBuilder: (_, i) {
                      final it = previewItems[i];
                      return CheckboxListTile(
                        value: it.include,
                        onChanged: (v) => setState(() => it.include = v!),
                        title: TextFormField(
                          initialValue: it.description,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                          onChanged: (t) => it.description = t,
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: it.total.toStringAsFixed(2),
                                decoration: const InputDecoration(labelText: 'Total'),
                                keyboardType: TextInputType.number,
                                onChanged: (t) {
                                  final p = double.tryParse(t);
                                  if (p != null) it.total = p;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('×${it.qty}'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  ctx,
                  ReceiptPreviewResult(previewItems, selectedPayer),
                );
              },
              child: const Text('Add Selected'),
            ),
          ],
        );
      }),
    );
  }

}
class _ReceiptPreviewItem {
  String description;
  int qty;
  double total;
  bool include;

  _ReceiptPreviewItem({
    required this.description,
    required this.qty,
    required this.total,
    this.include = true,
  });
}
class ReceiptPreviewResult {
  final List<_ReceiptPreviewItem> items;
  final String selectedPayer;
  ReceiptPreviewResult(this.items, this.selectedPayer);
}