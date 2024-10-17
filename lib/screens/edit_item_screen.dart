import 'package:flutter/material.dart';
import '../models/grocery_item.dart';
import '../services/database_service.dart';

class EditItemScreen extends StatefulWidget {
  final GroceryItem item;
  final String basketId;

  EditItemScreen({required this.item, required this.basketId});

  @override
  _EditItemScreenState createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late double _price;
  late int _quantity;

  @override
  void initState() {
    super.initState();
    _name = widget.item.name;
    _price = widget.item.price;
    _quantity = widget.item.quantity;
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
        optedInUserIds: widget.item.optedInUserIds,
      );

      await DatabaseService().updateItemInBasket(widget.basketId, updatedItem);

      Navigator.pop(context);
    }
  }

  void _deleteItem() async {
    await DatabaseService().deleteItemFromBasket(widget.basketId, widget.item.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
