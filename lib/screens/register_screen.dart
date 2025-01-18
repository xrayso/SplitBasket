import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  late String _userName;
  late String _email;
  late String _password;
  late String _confirmPassword;
  bool _isLoading = false;
  String? _errorMessage;

  void _register() async {

    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      if (_password != _confirmPassword) {
        setState(() {
          _errorMessage = 'Passwords do not match';
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });


        final String authenticatedMessage = await _authService.register(_email, _password, _userName);
        // Navigate to HomeScreen after successful registration
        if (authenticatedMessage == "Success") {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => MainScreen()),
                (route) => false,
          );
        }else{
          setState(() {
            _errorMessage = authenticatedMessage;
          });
        }
      }
      setState(() {
        _isLoading = false;
      });
    }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Register'),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Email Field
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                    value!.isEmpty ? 'Enter your email' : null,
                    onSaved: (value) => _email = value!,
                  ),
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Username'),
                    keyboardType: TextInputType.name,
                    validator: (value) =>
                    value!.isEmpty ? 'Enter your username' : null,
                    onSaved: (value) => _userName = value!,
                  ),
                  // Password Field
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (value) =>
                    value!.isEmpty ? 'Enter your password' : null,
                    onSaved: (value) => _password = value!,
                  ),
                  // Confirm Password Field
                  TextFormField(
                    decoration:
                    InputDecoration(labelText: 'Confirm Password'),
                    obscureText: true,
                    validator: (value) =>
                    value!.isEmpty ? 'Confirm your password' : null,
                    onSaved: (value) => _confirmPassword = value!,
                  ),
                  SizedBox(height: 20),
                  // Register Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    child: _isLoading
                        ? CircularProgressIndicator(
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                        : Text('Register'),
                  ),
                  // Error Message
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  // Navigate to Login
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text('Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}
