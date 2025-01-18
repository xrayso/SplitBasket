import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user.dart';
import 'search_users_screen.dart';
import 'friend_requests_screen.dart';

class FriendsListScreen extends StatelessWidget {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  FriendsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Friends'),
        actions: [
          StreamBuilder<User>(
            stream: _dbService.getUserStream(currentUserId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return IconButton(
                  icon: Icon(Icons.mail_outline),
                  onPressed: () {},
                );
              }

              User currentUser = snapshot.data!;
              int requestCount = currentUser.incomingFriendRequests.length;

              return IconButton(
                icon: badges.Badge(
                  badgeContent: Text(
                    requestCount.toString(),
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  showBadge: requestCount > 0,
                  position: badges.BadgePosition.topEnd(top: 0, end: 0),
                  child: Icon(Icons.mail_outline),
                ),
                tooltip: 'Friend Requests',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => FriendRequestsScreen()),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SearchUsersScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<User>(
        stream: _dbService.getUserStream(currentUserId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          User currentUser = snapshot.data!;
          List<String> friendIds = currentUser.friendIds;

          if (friendIds.isEmpty) {
            return Center(child: Text('You have no friends lol.'));
          }

          return ListView.builder(
            itemCount: friendIds.length,
            itemBuilder: (context, index) {
              return FutureBuilder<User>(
                future: _dbService.getUserById(friendIds[index]),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return ListTile(title: Text('Loading...'));
                  }

                  User friend = userSnapshot.data!;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      child: Text(
                        friend.userName.substring(0, 1).toUpperCase(),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(friend.userName),
                    subtitle: Text(friend.email),
                    trailing: IconButton(
                      icon: Icon(Icons.remove_circle_outline,
                          color: Colors.red),
                      onPressed: () {
                        _removeFriend(currentUserId, friend.id);
                      },
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

  void _removeFriend(String currentUserId, String friendId) async {
    await _dbService.removeFriend(currentUserId, friendId);
  }
}
