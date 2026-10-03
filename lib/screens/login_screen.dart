import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_layout.dart';
import 'register_screen.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  late String _email;
  late String _password;
  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMessage;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final String loginSuccessMessage = await _authService.signIn(_email.trim(), _password);
      if (!mounted) return;
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
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: AuthLayout(
              title: 'Welcome back',
              subtitle: 'Sign in to split your groceries with friends.',
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: (value) => value!.trim().isEmpty ? 'Enter your email' : null,
                  onSaved: (value) => _email = value!,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                      tooltip: _showPassword ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  obscureText: !_showPassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  validator: (value) => value!.isEmpty ? 'Enter your password' : null,
                  onSaved: (value) => _password = value!,
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
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading ? const ButtonSpinner() : const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => RegisterScreen()),
                    );
                  },
                  child: const Text("Don't have an account? Sign up"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
