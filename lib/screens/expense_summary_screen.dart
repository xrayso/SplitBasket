import 'package:flutter/material.dart';
import '../models/basket.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class ExpenseSummaryScreen extends StatefulWidget {
  final Basket basket;

  ExpenseSummaryScreen({required this.basket});

  @override
  _ExpenseSummaryScreenState createState() => _ExpenseSummaryScreenState();
}

class _ExpenseSummaryScreenState extends State<ExpenseSummaryScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  Map<String, double> balances = {};
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

    // Collect all user IDs to fetch their names later
    Set<String> userIds = Set();

    for (var item in widget.basket.items) {
      double totalCost = item.price * item.quantity;
      int numUsers = item.optedInUserIds.length;
      if (numUsers == 0) continue; // Avoid division by zero
      double costPerUser = totalCost / numUsers;

      for (var userId in item.optedInUserIds) {
        // Skip if the user is both the adder and opted-in user (they don't owe themselves)
        if (userId == hostId) continue;

        // Update balances
        if (userId == currentUserId) {
          // Current user owes to the adder
          tempBalances[hostId] = (tempBalances[hostId] ?? 0) + costPerUser;
        } else if (hostId == currentUserId) {
          // Other user owes to current user
          tempBalances[userId] = (tempBalances[userId] ?? 0) - costPerUser;
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
          : ListView.builder(
        itemCount: balances.length,
        itemBuilder: (context, index) {
          String otherUserId = balances.keys.elementAt(index);
          double amount = balances[otherUserId]!;
          String otherUserName = userNames[otherUserId] ?? 'Unknown User';

          String message;
          if (amount > 0) {
            // Current user owes this person
            message = 'You owe $otherUserName \$${amount.toStringAsFixed(2)}';
          } else if (amount < 0) {
            // This person owes current user
            message = '$otherUserName owes you \$${(-amount).toStringAsFixed(2)}';
          } else {
            // No balance
            message = 'You are settled with $otherUserName';
          }

          return ListTile(
            title: Text(message),
          );
        },
      ),
    );
  }
}
