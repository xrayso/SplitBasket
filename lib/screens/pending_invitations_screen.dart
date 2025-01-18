import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/basket.dart';

class PendingInvitationsScreen extends StatelessWidget {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  PendingInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Basket Invitations'),
      ),
      body: StreamBuilder<List<Basket>>(
        stream: _dbService.getInvitedBaskets(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading invitations'));
          }

          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          List<Basket> baskets = snapshot.data!;

          if (baskets.isEmpty) {
            return Center(child: Text('No pending invitations.'));
          }

          return ListView.builder(
            itemCount: baskets.length,
            itemBuilder: (context, index) {
              Basket basket = baskets[index];
              return FutureBuilder<String>(
                future: _dbService.getUserNameById(basket.hostId),
                builder: (context, snapshot) {
                  String hostName;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    hostName = "Loading...";
                  } else if (snapshot.hasError) {
                    hostName = "Error loading name";
                  } else {
                    hostName = snapshot.data ?? 'Anonymous';
                  }
                  return ListTile(
                    title: Text("Basket: ${basket.name}"),
                    subtitle: Text('Invited by: $hostName'),
                    // Optionally, fetch host's name
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.check, color: Colors.green),
                          tooltip: 'Accept',
                          onPressed: () =>
                              _acceptInvitation(basket.id, currentUserId),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.red),
                          tooltip: 'Decline',
                          onPressed: () =>
                              _declineInvitation(basket.id, currentUserId),
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

  void _acceptInvitation(String basketId, String userId) async {
    await _dbService.acceptBasketInvitation(basketId, userId);
  }

  void _declineInvitation(String basketId, String userId) async {
    await _dbService.declineBasketInvitation(basketId, userId);
  }
}
