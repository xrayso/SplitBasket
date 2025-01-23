import 'package:flutter/material.dart';
import '../models/basket.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class ExpenseSummaryScreen extends StatefulWidget {
  final Basket basket;

  const ExpenseSummaryScreen({super.key, required this.basket});

  @override
  _ExpenseSummaryScreenState createState() => _ExpenseSummaryScreenState();
}

class _ExpenseSummaryScreenState extends State<ExpenseSummaryScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  Map<String, double> balances = {};
  double totalBasketPrice = 0;
  Map<String, String> userNames = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateBalances();
  }

  Future<void> _calculateBalances() async {
    final currentUserId = _authService.currentUser!.uid;
    final String hostId = widget.basket.hostId;
    // Initialize balances map
    Map<String, double> tempBalances = {};
    double tempTotalCost = 0;
    // Collect all user IDs to fetch their names later
    Set<String> userIds = {};

    for (var item in widget.basket.items) {
      double totalCost = item.price * item.quantity;
      tempTotalCost += totalCost;
      int numUsers = item.userShares.length;
      if (numUsers == 0) continue; // Avoid division by zero

      for (var userId in item.userShares.keys) {
        // Skip if the user is both the adder and opted-in user (they don't owe themselves)
        if (userId == hostId) continue;
        double cost = item.userShares[userId]['share'] * totalCost;
        // Update balances
        if (userId == currentUserId) {
          // Current user owes to the adder
          tempBalances[hostId] = (tempBalances[hostId] ?? 0) + cost;
        } else if (hostId == currentUserId) {
          // Other user owes to current user
          tempBalances[userId] = (tempBalances[userId] ?? 0) - cost;
        }
        // Collect user IDs
        userIds.add(userId);
      }
    }

    // Fetch user names
    await _fetchUserNames(userIds);

    setState(() {
      balances = tempBalances;
      isLoading = false;
      totalBasketPrice = tempTotalCost;
    });
  }

  Future<void> _fetchUserNames(Set<String> userIds) async {
    for (var uid in userIds) {
      if (!userNames.containsKey(uid)) {
        String name = await _dbService.getUserNameById(uid);
        userNames[uid] = name;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Expense Summary'),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : balances.isEmpty
          ? Center(child: Text('No expenses to show.'))
          : Column(
        children: [
          // Compute and display the total price
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Total Basket Price: \$${totalBasketPrice.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            'After 13% Tax: \$${(totalBasketPrice * 1.13).toStringAsFixed(2)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: balances.length,
              itemBuilder: (context, index) {
                String otherUserId = balances.keys.elementAt(index);
                double amount = balances[otherUserId]!;

                String message;
                if (amount > 0) {
                  // Current user owes this person
                  message = 'You owe \$${amount.toStringAsFixed(2)}';
                } else if (amount < 0) {
                  // This person owes current user
                  message = 'You are owed \$${(-amount).toStringAsFixed(2)}';
                } else {
                  // No balance
                  message = 'You are even';
                }

                return ListTile(
                  title: Text(message),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
