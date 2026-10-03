import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user.dart';
import '../widgets/ui.dart';

class FriendRequestsScreen extends StatelessWidget {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Requests'),
      ),
      body: StreamBuilder<User>(
        stream: _dbService.getUserStream(currentUserId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final requestIds = snapshot.data!.incomingFriendRequests;
          if (requestIds.isEmpty) {
            return const EmptyState(
              icon: Icons.mark_email_read_outlined,
              title: 'No friend requests',
              message: "When someone adds you, you'll see it here.",
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requestIds.length,
            itemBuilder: (context, index) {
              return FutureBuilder<User>(
                future: _dbService.getUserById(requestIds[index]),
                builder: (context, userSnapshot) {
                  final sender = userSnapshot.data;
                  if (sender == null) return const ListTile(title: Text('…'));
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          PersonAvatar(name: sender.userName),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sender.userName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                Text('Wants to be friends', style: subtleText(context)),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _dbService.declineFriendRequest(
                                currentUserId, sender.id),
                            child: const Text('Decline'),
                          ),
                          const SizedBox(width: 4),
                          FilledButton(
                            onPressed: () => _dbService.acceptFriendRequest(
                                currentUserId, sender.id),
                            child: const Text('Accept'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
