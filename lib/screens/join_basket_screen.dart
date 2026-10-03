import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:split_basket/services/database_service.dart';
import 'basket_screen.dart';

class JoinBasketScreen extends StatefulWidget {
  const JoinBasketScreen({super.key});

  @override
  _JoinBasketScreenState createState() => _JoinBasketScreenState();
}

class _JoinBasketScreenState extends State<JoinBasketScreen> {
  final _formKey = GlobalKey<FormState>();
  String _invitationCode = '';
  bool _isLoading = false;
  String? _errorMessage;

  void _joinBasket() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
        String memberToken = await DatabaseService().getUserTokenById(currentUserId);
        final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('getBasketByInvitationCode');
        final result = await callable.call({'invitationCode': _invitationCode, 'memberToken' : memberToken});

        if (result.data == null || result.data['basketId'] == null) {
          setState(() {
            _errorMessage = 'Invalid invitation code.';
          });
        } else {
          String basketId = result.data['basketId'];
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => BasketScreen(basketId: basketId)),
          );
        }
      } on FirebaseFunctionsException catch (e) {
        setState(() {
          _errorMessage = e.message;
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a Basket')),
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
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.go,
                  style: const TextStyle(fontSize: 22, letterSpacing: 4),
                  decoration: const InputDecoration(
                    labelText: 'Invite code',
                    hintText: 'ABC123',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the code your friend shared.';
                    }
                    return null;
                  },
                  onChanged: (value) => _invitationCode = value.trim().toUpperCase(),
                  onFieldSubmitted: (_) => _joinBasket(),
                ),
                const SizedBox(height: 8),
                Text(
                  "Ask the basket's host for it. It's on their Members tab.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _joinBasket,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Join basket'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
