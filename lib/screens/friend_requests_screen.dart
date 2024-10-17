import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user.dart';

class FriendRequestsScreen extends StatelessWidget {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  @override
  Widget build(BuildContext context) {
    final String currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Friend Requests'),
      ),
      body: StreamBuilder<User>(
        stream: _dbService.getUserStream(currentUserId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          User currentUser = snapshot.data!;
          List<String> requestIds = currentUser.incomingFriendRequests;

          if (requestIds.isEmpty) {
            return Center(child: Text('No friend requests.'));
          }

          return ListView.builder(
            itemCount: requestIds.length,
            itemBuilder: (context, index) {
              String senderId = requestIds[index];
              return FutureBuilder<User>(
                future: _dbService.getUserById(senderId),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return ListTile(title: Text('Loading...'));
                  }

                  User sender = userSnapshot.data!;
                  return Dismissible(
                    key: Key(sender.id),
                    background: Container(
                      color: Colors.green,
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.symmetric(horizontal: 20.0),
                      child: Icon(Icons.check, color: Colors.white),
                    ),
                    secondaryBackground: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: EdgeInsets.symmetric(horizontal: 20.0),
                      child: Icon(Icons.close, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        await _dbService.acceptFriendRequest(
                            currentUserId, sender.id);
                        return true;
                      } else if (direction ==
                          DismissDirection.endToStart) {
                        await _dbService.declineFriendRequest(
                            currentUserId, sender.id);
                        return true;
                      }
                      return false;
                    },
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        child: Text(
                          sender.userName.substring(0, 1).toUpperCase(),
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(sender.userName),
                      subtitle: Text('Sent you a friend request'),
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

  void _acceptFriendRequest(String currentUserId, String senderId) async {
    await _dbService.acceptFriendRequest(currentUserId, senderId);
  }

  void _declineFriendRequest(
      String currentUserId, String senderId) async {
    await _dbService.declineFriendRequest(currentUserId, senderId);
  }
}
