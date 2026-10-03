import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user.dart';
import '../widgets/ui.dart';
import 'search_users_screen.dart';
import 'friend_requests_screen.dart';

class FriendsListScreen extends StatefulWidget {
  const FriendsListScreen({super.key});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  late final String _uid = _authService.currentUser!.uid;
  // Created once, so switching tabs doesn't re-download everything.
  late final Stream<User> _me = _dbService.getUserStream(_uid);

  void _addFriends() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchUsersScreen()),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User>(
      stream: _me,
      builder: (context, snapshot) {
        final me = snapshot.data;
        final requestCount = me?.incomingFriendRequests.length ?? 0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Friends'),
            actions: [
              IconButton(
                tooltip: 'Friend requests',
                icon: Badge(
                  isLabelVisible: requestCount > 0,
                  label: Text('$requestCount'),
                  child: const Icon(Icons.mail_outline),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FriendRequestsScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Add friends',
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: _addFriends,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: me == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (requestCount > 0) _requestsBanner(requestCount),
                    if (me.friendIds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 64),
                        child: EmptyState(
                          icon: Icons.people_outline,
                          title: 'No friends yet',
                          message: 'Add friends with their friend tag, like '
                              '${me.userName}#${me.friendCode}. Yours is in your profile.',
                          action: FilledButton.icon(
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Add friends'),
                            onPressed: _addFriends,
                          ),
                        ),
                      ),
                    for (final friendId in me.friendIds)
                      FutureBuilder<User>(
                        future: _dbService.getUserById(friendId),
                        builder: (context, userSnapshot) {
                          final friend = userSnapshot.data;
                          if (friend == null) {
                            return const ListTile(title: Text('…'));
                          }
                          return ListTile(
                            leading: PersonAvatar(name: friend.userName),
                            title: Text(friend.userName),
                            subtitle: Text('${friend.userName}#${friend.friendCode}'),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'More',
                              onSelected: (_) => _confirmRemove(friend),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove friend'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _requestsBanner(int count) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ListTile(
        leading: Icon(Icons.mark_email_unread_outlined,
            color: scheme.onSecondaryContainer),
        title: Text(
          count == 1 ? '1 friend request' : '$count friend requests',
          style: TextStyle(
              color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FriendRequestsScreen()),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(User friend) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${friend.userName}?'),
        content: const Text(
            "You'll stop being friends. Baskets and charges you share aren't affected."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _dbService.removeFriend(_uid, friend.id);
  }
}
