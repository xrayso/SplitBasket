import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user.dart';

class FriendRequestsScreen extends StatelessWidget {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  FriendRequestsScreen({super.key});

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
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      child: Text(
                        sender.userName.substring(0, 1).toUpperCase(),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(sender.userName),
                    subtitle: Text('Sent you a friend request'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await _dbService.acceptFriendRequest(
                                currentUserId, sender.id);
                          },
                          child: Text('Accept'),
                        ),
                        SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            await _dbService.declineFriendRequest(
                                currentUserId, sender.id);
                          },
                          child: Text('Decline'),
                        ),
                      ],
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
