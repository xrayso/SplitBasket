import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_layout.dart' show ButtonSpinner;
import '../widgets/ui.dart';

/// Explains what deleting an account does, then deletes it once the user
/// enters their password.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _auth = AuthService();
  final _password = TextEditingController();
  bool _hidden = true;
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await _auth.deleteAccount(_password.text);
    if (error != null) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = error;
        });
      }
      return;
    }
    navigator.pushNamedAndRemoveUntil('/login', (_) => false);
    messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')));
  }

  Future<void> _forgotPassword() async {
    final email = _auth.currentUser?.email;
    if (email == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _auth.sendPasswordReset(email);
      messenger.showSnackBar(
          SnackBar(content: Text('We sent a reset link to $email.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't send a reset link. Try again later.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text('This permanently deletes your account.',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const _Point(
            icon: Icons.person_off_outlined,
            text: 'Your profile, friend tag and friends list are deleted.',
          ),
          const _Point(
            icon: Icons.receipt_long_outlined,
            text: 'Receipt photos you scanned are deleted, along with baskets '
                'only you are in.',
          ),
          const _Point(
            icon: Icons.group_outlined,
            text: "You leave your shared baskets. Items and charges you share "
                'with other people stay, shown as "Deleted user", so their '
                'totals still add up.',
          ),
          const _Point(
            icon: Icons.link_off_rounded,
            text: 'Connected stores are disconnected on this phone.',
          ),
          const SizedBox(height: 16),
          Text("This can't be undone.",
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          TextField(
            controller: _password,
            obscureText: _hidden,
            enabled: !_deleting,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _password.text.isEmpty ? null : _delete(),
            decoration: InputDecoration(
              labelText: 'Your password',
              helperText: "To confirm it's you",
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                tooltip: _hidden ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _deleting ? null : _forgotPassword,
              child: const Text('Forgot your password?'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed:
                _deleting || _password.text.isEmpty ? null : _delete,
            child: _deleting
                ? const ButtonSpinner()
                : const Text('Delete my account'),
          ),
          const SizedBox(height: 16),
          Text(
            "Can't sign in? You can also ask for your account to be deleted "
            'at splitbasketapp.web.app/delete-account.',
            style: subtleText(context),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Point({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
