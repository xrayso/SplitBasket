import 'package:flutter/material.dart';
import '../models/grocery_item.dart';
import '../services/database_service.dart';
import '../screens/edit_item_screen.dart';

class GroceryItemTile extends StatefulWidget {
  final GroceryItem item;
  final Future<void> Function() onTap;
  final bool isOptedIn;
  final String basketId;
  final bool isFinalized;

  GroceryItemTile({
    Key? key,
    required this.item,
    required this.onTap,
    required this.isOptedIn,
    required this.basketId,
    this.isFinalized = false,
  }) : super(key: key);

  @override
  _GroceryItemTileState createState() => _GroceryItemTileState();
}

class _GroceryItemTileState extends State<GroceryItemTile> {
  late Future<List<String>> _optedInUsernamesFuture;

  @override
  void initState() {
    super.initState();
    _optedInUsernamesFuture = _fetchOptedInUsernames();
  }

  Future<List<String>> _fetchOptedInUsernames() async {
    final DatabaseService _dbService = DatabaseService();
    List<String> usernames = [];

    for (String uid in widget.item.optedInUserIds) {
      String username = await _dbService.getUserNameById(uid);
      usernames.add(username);
    }

    return usernames;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2.0,
      margin:
      EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: ListTile(
        title: Text(
          '${widget.item.name} \$${(widget.item.price * widget.item.quantity).toStringAsFixed(2)}',
          style: TextStyle(
              decoration: widget.isOptedIn
                  ? TextDecoration.underline
                  : TextDecoration.none),
        ),
        subtitle: FutureBuilder<List<String>>(
          future: _optedInUsernamesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Text('Opted in: ');
            } else if (snapshot.hasError) {
              return Text('Opted in: ');
            } else {
              String usernames = snapshot.data!.join(', ');
              return Text('Opted in: $usernames');
            }
          },
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isFinalized)
              IconButton(
                icon: Icon(
                  widget.isOptedIn
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color:
                  widget.isOptedIn ? Colors.green : null,
                ),
                onPressed: _toggleOptIn,
              ),
            if (!widget.isFinalized)
              IconButton(
                icon: Icon(Icons.edit),
                onPressed: _editItem,
              ),
          ],
        ),
      ),
    );
  }

  void _editItem() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditItemScreen(
          item: widget.item,
          basketId: widget.basketId,
        ),
      ),
    );
  }

  void _toggleOptIn() async {
    await widget.onTap();
    setState(() {
      _optedInUsernamesFuture = _fetchOptedInUsernames();
    });
  }
}
