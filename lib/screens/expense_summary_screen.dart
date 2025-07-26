import 'package:flutter/material.dart';
import 'package:split_basket/models/aggregated_charge.dart';
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

  Map<String, Map<String, double>> balances = {};
  double totalBasketPrice = 0;
  Map<String, String> userNames = {};
  bool isLoading = true;
  late String currentUserId;
  @override
  void initState() {
    currentUserId = _authService.currentUser!.uid;
    super.initState();
    calculateBalances();
  }

  Future<void> calculateBalances() async{
    balances = {};
    double tempTotalCost = 0;
    for (var item in widget.basket.items){
      tempTotalCost += item.quantity * item.price;
      for (var userId in item.userShares.keys){

        String key = userId.compareTo(item.paidBy) > 0 ? userId : item.paidBy;
        String secondKey = userId.compareTo(item.paidBy) <= 0 ? userId : item.paidBy;
        if (key == secondKey) continue;
        double cost = item.userShares[userId]['share'] * item.price * item.quantity;
        if (key == item.paidBy) cost = -cost;
        if (balances[key] == null) {
          balances[key] = {secondKey : cost};
        }else{
          balances[key]![secondKey] = (balances[key]![secondKey] ?? 0) + cost;
        }
      }
    }

    Iterable<String> keys = List<String>.from(balances.keys);
    print(balances);
    for (var key in keys){
      for (var entry2 in balances[key]!.entries) {
        if (balances[entry2.key] == null){
          balances[entry2.key] = {key: -entry2.value};
        }else {
          balances[entry2.key]![key] = -entry2.value;
        }
      }
    }
    print(balances);

    await _fetchUserNames();
    setState(() {
      isLoading = false;
      totalBasketPrice = tempTotalCost;
      balances = balances;
    });
  }


  Future<void> _fetchUserNames() async {
    for (var uid in widget.basket.memberIds) {
      if (!userNames.containsKey(uid)) {
        String name = await _dbService.getUserNameById(uid);
        userNames[uid] = name;
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text('Expense Summary'),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : totalBasketPrice == 0
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
              itemCount: balances[currentUserId]?.length ?? 0,
              itemBuilder: (context, index) {
                String otherUserId = balances[currentUserId]!.keys.elementAt(index);
                double amount = balances[currentUserId]![otherUserId]!;

                String message;
                if (amount > 0) {
                  // Current user owes this person
                  message = 'You owe \$${amount.toStringAsFixed(2)} to ${userNames[otherUserId]}';
                } else if (amount < 0) {
                  // This person owes current user
                  message = '${userNames[otherUserId]} owes you \$${(-amount).toStringAsFixed(2)}';
                } else {
                  // No balance
                  message = '';
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
