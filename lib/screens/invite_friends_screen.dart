import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

class InviteFriendsScreen extends StatefulWidget {
  final String basketId;

  InviteFriendsScreen({required this.basketId});

  @override
  _InviteFriendsScreenState createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<User> _friends = [];
  List<String> _selectedFriendIds = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  void _loadFriends() async {
    User currentUser = await _dbService.getUserById(_authService.currentUser!.uid);
    List<String> friendIds = currentUser.friendIds;

    List<User> friends = [];
    for (String friendId in friendIds) {
      User friend = await _dbService.getUserById(friendId);
      friends.add(friend);
    }

    setState(() {
      _friends = friends;
    });
  }

  void _inviteFriends() async {
    await _dbService.inviteFriendsToBasket(widget.basketId, _selectedFriendIds);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Invite Friends')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                children: _friends.map((friend) {
                  return CheckboxListTile(
                    title: Text(friend.userName),
                    value: _selectedFriendIds.contains(friend.id),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedFriendIds.add(friend.id);
                        } else {
                          _selectedFriendIds.remove(friend.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            ElevatedButton(
              onPressed: _inviteFriends,
              child: Text('Send Invitations'),
            ),
          ],
        ));
  }
}
