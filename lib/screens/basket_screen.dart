import 'package:flutter/material.dart';
import '../models/basket.dart';
import 'basket_members_screen.dart';
import 'expense_summary_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/grocery_item_tile.dart';
import '../models/grocery_item.dart';
import 'main_screen.dart';
import 'add_item_screen.dart';

class BasketScreen extends StatefulWidget {
  final String basketId;

  BasketScreen({required this.basketId});

  @override
  _BasketScreenState createState() => _BasketScreenState();
}

class _BasketScreenState extends State<BasketScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  int _currentIndex = 1; // Start with the middle tab selected
  late PageController _pageController; // Declare PageController

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController
        .dispose(); // Dispose of the controller when the widget is removed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return StreamBuilder<Basket>(
      stream: _dbService.streamBasket(widget.basketId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => MainScreen()), (
                    route) => false);
          });
          return Scaffold(
            appBar: AppBar(title: Text('Basket')),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text('Basket')),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        Basket basket = snapshot.data!;
        // List of pages for the bottom navigation
        final List<Widget> _pages = [
          // Left Tab: Basket Members Screen
          BasketMembersScreen(basket: basket),
          // Middle Tab: Main Basket Page
          Scaffold(
            appBar: AppBar(
              title: Text(basket.name),
              actions: [
                if (basket.hostId == currentUserId)
                  IconButton(
                    icon: Icon(Icons.check),
                    tooltip: 'Finalize Basket',
                    onPressed: () => _finalizeBasket(context, basket),
                  ),
                if (basket.hostId == currentUserId)
                  IconButton(
                    icon: Icon(Icons.delete),
                    tooltip: 'Delete Basket',
                    onPressed: () => _deleteBasket(context, basket),
                  ),
              ],
            ),
            body: basket.items.isEmpty
                ? Center(child: Text('No items added yet.'))
                : ListView.builder(
              itemCount: basket.items.length,
              itemBuilder: (context, index) {
                final item = basket.items[index];
                final isOptedIn =
                item.optedInUserIds.contains(currentUserId);
                return GroceryItemTile(
                  key: ValueKey(item.id),
                  item: item,
                  onTap: () async {
                    await _toggleOptIn(item, basket.id);
                  },
                  isOptedIn: isOptedIn,
                  basketId: widget.basketId,
                );
              },
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddItemScreen(basketId: basket.id),
                  ),
                );
              },
              child: Icon(Icons.add),
            ),
          ),
          // Right Tab: Expense Summary Screen
          ExpenseSummaryScreen(basket: basket),
        ];

        return Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index; // Update the current index when swiped
              });
            },
            children: _pages,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            selectedItemColor: Theme
                .of(context)
                .colorScheme
                .secondary,
            items: [
              BottomNavigationBarItem(
                icon: Icon(Icons.people),
                label: 'Members',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.shopping_cart),
                label: 'Basket',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt),
                label: 'Summary',
              ),
            ],
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
              // Animate to the page when the bottom navigation item is tapped
              _pageController.animateToPage(
                index,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        );
      },
    );
  }

  void _finalizeBasket(BuildContext context, Basket basket) async {
    final String finalizeError = basket.items.isEmpty
        ? "You cannot finalize a basket with no items. Please add items to the basket before finalizing"
        : "All items must have at least one opted-in user before finalizing.";
    if (basket.items.isEmpty ||
        basket.items.any((item) => item.optedInUserIds.isEmpty)) {
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
    bool confirm = await showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text("Finalize Basket"),
            content: Text('Are you sure you want to finalize this basket?'),
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
    if (confirm) await _dbService.finalizeBasket(basket);
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

  Future<void> _toggleOptIn(GroceryItem item, String basketId) async {
    final currentUserId = _authService.currentUser!.uid;
    await _dbService.toggleOptIn(item, basketId, currentUserId);
  }
}