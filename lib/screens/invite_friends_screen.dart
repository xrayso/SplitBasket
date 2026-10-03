import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../widgets/ui.dart';

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
  bool _loading = true;
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
    _loading = false;

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
      appBar: AppBar(title: const Text('Invite Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No friends to invite yet',
                  message: 'Add friends from the Friends tab, or share the '
                      "basket's invite code from the Members tab.",
                )
              : ListView(
                  children: _friends.map((friend) {
                    return CheckboxListTile(
                      secondary: PersonAvatar(name: friend.userName),
                      title: Text(friend.userName),
                      subtitle: Text('${friend.userName}#${friend.friendCode}'),
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
      bottomNavigationBar: _friends.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _selectedFriendIds.isEmpty ? null : _inviteFriends,
                  child: Text(_selectedFriendIds.length > 1
                      ? 'Invite ${_selectedFriendIds.length} friends'
                      : 'Send invitation'),
                ),
              ),
            ),
    );
  }
}
