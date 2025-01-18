import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/basket.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'invite_friends_screen.dart';

class BasketMembersScreen extends StatelessWidget {
  final Basket basket;
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  BasketMembersScreen({super.key, required this.basket});

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;
    final isHost = basket.hostId == currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Basket Members'),
        actions: [
          if (isHost)
            IconButton(
              icon: Icon(Icons.person_add),
              onPressed: () => _inviteFriends(context),
            ),
          if (isHost)
            IconButton(
              icon: Icon(Icons.share),
              onPressed: () {
              Share.share('Join my basket using this code: ${basket.invitationCode}');
              },
            )
        ],
      ),
      body: FutureBuilder<List<User>>(
        future: _getMembers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading members.'));
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          final members = snapshot.data!;
          return ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    member.userName.substring(0, 1).toUpperCase(),
                  ),
                ),
                title: Text(member.userName),
                subtitle: Text(member.email),
                trailing: isHost && member.id != basket.hostId
                    ? IconButton(
                  icon: Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => _removeMember(member.id),
                )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _inviteFriends(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InviteFriendsScreen(basketId: basket.id),
      ),
    );
  }

  Future<List<User>> _getMembers() async {
    List<User> members = [];
    for (String memberId in basket.memberIds) {
      User member = await _dbService.getUserById(memberId);
      members.add(member);
    }
    // Ensure the host is at the top
    members.sort((a, b) {
      if (a.id == basket.hostId) return -1;
      if (b.id == basket.hostId) return 1;
      return 0;
    });
    return members;
  }

  Future<void> _removeMember(String memberId) async {
    basket.memberIds.remove(memberId);
    await _dbService.updateBasketMembers(basket.id, basket.memberIds);
  }
}
