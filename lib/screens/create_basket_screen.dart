import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/basket.dart';
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
      final basketId = Uuid().v4();
      final invitationCode = _generateInvitationCode();
      final currentUserId = _authService.currentUser!.uid;
      final newBasket = Basket(
        id: basketId,
        name: _basketName,
        hostId: currentUserId,
        memberIds: [currentUserId],
        memberTokens: [],
        invitationCode: invitationCode,
      );
      await _dbService.setBasket(newBasket);
      Navigator.pop(context);
    }
  }

  String _generateInvitationCode(){
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Basket'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: InputDecoration(labelText: 'Basket Name'),
                validator: (value) =>
                value == null || value.isEmpty ? 'Enter a basket name' : null,
                onSaved: (value) => _basketName = value!,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _createBasket,
                child: Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
