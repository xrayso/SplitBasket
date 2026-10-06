import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class CreateBasketScreen extends StatefulWidget {
  const CreateBasketScreen({super.key});

  @override
  _CreateBasketScreenState createState() => _CreateBasketScreenState();
}

class _CreateBasketScreenState extends State<CreateBasketScreen> {
  final _formKey = GlobalKey<FormState>();
  String _basketName = '';

  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  void _createBasket() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      await _dbService.createBasket(_basketName, _authService.currentUser!.uid);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Basket'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Basket name',
                    hintText: 'e.g. Costco run',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Enter a basket name' : null,
                  onSaved: (value) => _basketName = value!.trim(),
                  onFieldSubmitted: (_) => _createBasket(),
                ),
                const SizedBox(height: 8),
                Text(
                  "You'll be the host. Invite friends from the basket's Members tab.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _createBasket,
                  child: const Text('Create basket'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
