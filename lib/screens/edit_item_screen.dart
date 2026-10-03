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
  late final String _priceText = widget.item.price.toStringAsFixed(2);
  late int _quantity;
  late String _paidBy;
  late bool _taxable;
  final Map<String, User> _basketUsers = {};

  @override

  void initState() {
    super.initState();
    _name = widget.item.name;
    _price = widget.item.price;
    _quantity = widget.item.quantity;
    _paidBy = widget.item.paidBy;
    _taxable = widget.item.taxable;
    getBasketNames();
  }
  Future<void> getBasketNames() async{
    for (String userId in widget.basket.memberIds){
      _basketUsers[userId] = await _dbService.getUserById(userId);
    }

    if (mounted) setState(() {});
  }

  void _saveItem() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      GroceryItem updatedItem = widget.item.copyWith(
        name: _name,
        price: _price,
        quantity: _quantity,
        paidBy: _paidBy,
        taxable: _taxable,
      );

      await _dbService.updateItemInBasket(widget.basket.id, updatedItem);

      Navigator.pop(context);
    }
  }

  void _deleteItem() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.item.name}?'),
        content: const Text("It'll be removed from the basket for everyone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _dbService.deleteItemFromBasket(widget.basket.id, widget.item.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Item'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete item',
            onPressed: _deleteItem,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              initialValue: _name,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Item name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter item name' : null,
              onSaved: (value) => _name = value!.trim(),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: _priceText,
                    decoration: const InputDecoration(
                        labelText: 'Price (each)', prefixText: '\$'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                    validator: (value) =>
                        double.tryParse(value ?? '') == null ? 'Enter a price' : null,
                    // Untouched, keep the exact price (e.g. 3 for \$13 is
                    // 4.333…), so saving other changes doesn't round it.
                    onSaved: (value) {
                      if (value != _priceText) _price = double.parse(value!);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: _quantity.toString(),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final qty = int.tryParse(value ?? '');
                      return qty == null || qty < 1 ? 'At least 1' : null;
                    },
                    onSaved: (value) => _quantity = int.parse(value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Paid by'),
              initialValue: widget.item.paidBy,
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
              onPressed: _saveItem,
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
