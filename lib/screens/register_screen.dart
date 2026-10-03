import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_layout.dart';
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

      final String authenticatedMessage =
          await _authService.register(_email.trim(), _password, _userName.trim());
      if (!mounted) return;
      // Navigate to HomeScreen after successful registration
      if (authenticatedMessage == "Success") {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => MainScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _errorMessage = authenticatedMessage;
        });
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: AuthLayout(
              title: 'Create your account',
              subtitle: 'Friends find you by your username.',
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Enter a username' : null,
                  onSaved: (value) => _userName = value!,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Enter your email' : null,
                  onSaved: (value) => _email = value!,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      value!.isEmpty ? 'Enter a password' : null,
                  onSaved: (value) => _password = value!,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  validator: (value) =>
                      value!.isEmpty ? 'Confirm your password' : null,
                  onSaved: (value) => _confirmPassword = value!,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading ? const ButtonSpinner() : const Text('Create account'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Already have an account? Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
