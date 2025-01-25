import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
      appBar: AppBar(title: Text('Join a Basket')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: InputDecoration(labelText: 'Invitation Code'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a valid invitation code.';
                  }
                  return null;
                },
                onChanged: (value) => _invitationCode = value,
              ),
              SizedBox(height: 20),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red),
                ),
              SizedBox(height: 20),
              _isLoading
                  ? CircularProgressIndicator()
                  : ElevatedButton(
                onPressed: _joinBasket,
                child: Text('Join Basket'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
