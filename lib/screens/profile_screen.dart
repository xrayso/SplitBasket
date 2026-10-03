// profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../services/database_service.dart';
import '../models/user.dart' as app_user;
import '../widgets/ui.dart';

class ProfileScreen extends StatelessWidget {
  final DatabaseService _databaseService = DatabaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String currentUserId = _auth.currentUser!.uid;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: FutureBuilder<app_user.User>(
        future: _databaseService.getUserById(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(child: Text('No user data found'));
          }

          final user = snapshot.data!;
          final tag = '${user.userName}#${user.friendCode}';
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: PersonAvatar(name: user.userName, radius: 44)),
              const SizedBox(height: 16),
              Text(
                user.userName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(user.email, textAlign: TextAlign.center, style: subtleText(context)),
              const SizedBox(height: 28),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                  title: Text('Your friend tag', style: subtleText(context)),
                  subtitle: Text(
                    tag,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tag));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Friend tag copied')),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Friends can add you by searching for this tag.',
                  style: subtleText(context),
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                ),
                onPressed: () async {
                  await _auth.signOut();
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
