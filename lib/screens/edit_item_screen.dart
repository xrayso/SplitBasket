import 'package:flutter/material.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../models/user.dart';
import '../services/database_service.dart';

class EditItemScreen extends StatefulWidget {
  final GroceryItem item;
  final Basket basket;

  const EditItemScreen({super.key, required this.item, required this.basket});

  @override
  _EditItemScreenState createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  late String _name;
  late double _price;
  late int _quantity;
  late String _paidBy;
  bool _loading = true;
  final Map<String, User> _basketUsers = {};

  @override

  void initState() {
    super.initState();
    _name = widget.item.name;
    _price = widget.item.price;
    _quantity = widget.item.quantity;
    _paidBy = widget.item.paidBy;
  }
  Future<void> getBasketNames() async{
    for (String userId in widget.basket.memberIds){
      _basketUsers[userId] = await _dbService.getUserById(userId);
    }

    setState(() {
      _loading = false;
    });


  }

  void _saveItem() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      GroceryItem updatedItem = GroceryItem(
        id: widget.item.id,
        name: _name,
        price: _price,
        quantity: _quantity,
        addedBy: widget.item.addedBy,
        userShares: widget.item.userShares,
        paidBy: _paidBy,
      );

      await _dbService.updateItemInBasket(widget.basket.id, updatedItem);

      Navigator.pop(context);
    }
  }

  void _deleteItem() async {
    await _dbService.deleteItemFromBasket(widget.basket.id, widget.item.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    getBasketNames();
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Item'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: _deleteItem,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Item Name
              TextFormField(
                initialValue: _name,
                decoration: InputDecoration(labelText: 'Item Name'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Enter item name' : null,
                onSaved: (value) => _name = value!,
              ),
              // Price
              TextFormField(
                initialValue: _price.toString(),
                decoration: InputDecoration(labelText: 'Price'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) =>
                value == null || value.isEmpty ? 'Enter price' : null,
                onSaved: (value) => _price = double.parse(value!),
              ),
              // Quantity
              TextFormField(
                initialValue: _quantity.toString(),
                decoration: InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                value == null || value.isEmpty ? 'Enter quantity' : null,
                onSaved: (value) => _quantity = int.parse(value!),
              ),

              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Paid By'),
                value: widget.item.paidBy, // Current selection
                items: widget.basket.memberIds.map((userIds) {
                  return DropdownMenuItem<String>(
                    value: userIds,
                    child: Text(_basketUsers[userIds]?.userName ?? ""),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _paidBy = val!;
                  });
                },
              ),

              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveItem,
                child: Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
