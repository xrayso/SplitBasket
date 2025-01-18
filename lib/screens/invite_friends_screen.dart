import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

class InviteFriendsScreen extends StatefulWidget {
  final String basketId;

  const InviteFriendsScreen({super.key, required this.basketId});

  @override
  _InviteFriendsScreenState createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<User> _friends = [];
  final List<String> _selectedFriendIds = [];

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
                    subtitle: Text(friend.email),
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
            SizedBox(height: 20), // Adds space above the button
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: ElevatedButton(
                onPressed: _inviteFriends,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 15.0),
                  minimumSize: Size(double.infinity, 50), // Makes the button full-width
                ),
                child: Text('Send Invitations'),
              ),
            ),
            SizedBox(height: 20), // Adds space below the button
          ],
        ));
  }
}
