import 'package:flutter/material.dart';
import 'package:split_basket/services/auth_service.dart';
import 'package:uuid/uuid.dart';
import '../models/basket.dart';
import '../models/grocery_item.dart';
import '../models/user.dart';
import '../services/database_service.dart';

class AddItemScreen extends StatefulWidget {
  final Basket basket;

  const AddItemScreen({super.key, required this.basket});

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
  late String _paidBy;
  bool _taxable = false;
  final Map<String, User> _basketUsers = {};

  @override
  void initState() {
    _paidBy = AuthService().currentUser!.uid;
    super.initState();
    getBasketNames();
  }

  Future<void> getBasketNames() async{
    for (String userId in widget.basket.memberIds){
      _basketUsers[userId] = await _dbService.getUserById(userId);
    }

    if (mounted) setState(() {});


  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Item'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Item name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter the item name';
                }
                return null;
              },
              onSaved: (value) {
                _itemName = value!.trim();
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    decoration: const InputDecoration(
                        labelText: 'Price (each)', prefixText: '\$'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null ||
                          value.isEmpty ||
                          double.tryParse(value) == null) {
                        return 'Enter a price';
                      }
                      return null;
                    },
                    onSaved: (value) {
                      _itemPrice = double.parse(value!);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: '1',
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: false),
                    validator: (value) {
                      final qty = int.tryParse(value ?? '');
                      if (qty == null || qty < 1) {
                        return 'At least 1';
                      }
                      return null;
                    },
                    onSaved: (value) {
                      _itemQuantity = int.parse(value!);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Paid by'),
              initialValue: _paidBy,
              items: widget.basket.memberIds.map((userIds) {
                return DropdownMenuItem<String>(
                  value: userIds,
                  child: Text(_basketUsers[userIds]?.userName ?? '…'),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _paidBy = val!;
                });
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Taxed'),
              subtitle: const Text('Sales tax was charged on this item'),
              value: _taxable,
              onChanged: (v) => setState(() => _taxable = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitForm,
              child: const Text('Add item'),
            ),
          ],
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
        paidBy: _paidBy,
        userShares: {},
        taxable: _taxable,
      );
      await _dbService.addItemToBasket(widget.basket.id, newItem);
      Navigator.pop(context);
    }
  }
}
