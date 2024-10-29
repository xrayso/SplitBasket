import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  late String _email;
  late String _password;
  bool _isLoading = false;
  String? _errorMessage;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() { _isLoading = true; });

      final String loginSuccessMessage = await _authService.signIn(_email, _password);
      if (loginSuccessMessage == "Success"){
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainScreen()),
        );
      } else {
        setState(() { _errorMessage = loginSuccessMessage; });
      }
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Login'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Email Field
              TextFormField(
                decoration: InputDecoration(labelText: 'Email'),
                validator: (value) => value!.isEmpty ? 'Enter email' : null,
                onSaved: (value) => _email = value!,
              ),
              // Password Field
              TextFormField(
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) => value!.isEmpty ? 'Enter password' : null,
                onSaved: (value) => _password = value!,
              ),
              SizedBox(height: 20),
              // Login Button
              ElevatedButton(
                onPressed: _login,
                child: _isLoading ? CircularProgressIndicator() : Text('Login'),
              ),
              // Error Message
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red),
                ),
              // Navigate to Register
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => RegisterScreen()),
                  );
                },
                child: Text('Don\'t have an account? Register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
