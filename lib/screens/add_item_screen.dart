import 'package:flutter/material.dart';
import 'package:split_basket/services/auth_service.dart';
import 'package:uuid/uuid.dart';
import '../models/grocery_item.dart';
import '../services/database_service.dart';

class AddItemScreen extends StatefulWidget {
  final String basketId;

  const AddItemScreen({super.key, required this.basketId});

  @override
  _AddItemScreenState createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  late String _itemName;
  late double _itemPrice;
  late int _itemQuantity;
  late String _addedBy;
  late String basketId;


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add New Item'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Item Name
              TextFormField(
                decoration: InputDecoration(labelText: 'Item Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the item name';
                  }
                  return null;
                },
                onSaved: (value) {
                  _itemName = value!;
                },
              ),
              // Item Price
              TextFormField(
                decoration: InputDecoration(labelText: 'Price'),
                keyboardType:
                TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null ||
                      value.isEmpty ||
                      double.tryParse(value) == null) {
                    return 'Please enter a valid price';
                  }
                  return null;
                },
                onSaved: (value) {
                  _itemPrice = double.parse(value!);
                },
              ),
              // Item Quantity
              TextFormField(
                decoration: InputDecoration(labelText: 'Quantity'),
                keyboardType:
                TextInputType.numberWithOptions(decimal: false),
                validator: (value) {
                  if (value == null ||
                      value.isEmpty ||
                      int.tryParse(value) == null) {
                    return 'Please enter a valid quantity';
                  }
                  return null;
                },
                onSaved: (value) {
                  _itemQuantity = int.parse(value!);
                },
              ),
              // Added By
              SizedBox(height: 20),
              // Submit Button
              ElevatedButton(
                onPressed: _submitForm,
                child: Text('Add Item'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      _addedBy = AuthService().currentUser!.uid;
      final newItem = GroceryItem(
        id: Uuid().v4(),
        name: _itemName,
        price: _itemPrice,
        quantity: _itemQuantity,
        addedBy: _addedBy,
        userShares: {},
      );
      await DatabaseService().addItemToBasket(widget.basketId, newItem);
      Navigator.pop(context);
    }
  }
}
