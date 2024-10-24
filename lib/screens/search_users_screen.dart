import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

class SearchUsersScreen extends StatefulWidget {
  @override
  _SearchUsersScreenState createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  String _searchQuery = '';
  List<User> _searchResults = [];
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  String _currentUserId = '';
  List<String> _friendIds = [];
  List<String> _outgoingFriendRequests = [];
  List<String> _incomingFriendRequests = [];

  @override
  void initState() {
    super.initState();
    _getCurrentUserData();
  }

  // Fetch current user's data including friend lists and friend requests
  void _getCurrentUserData() async {
    final currentUserId = _authService.currentUser!.uid;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .get();

    if (userDoc.exists) {
      final data = userDoc.data()!;
      setState(() {
        _currentUserId = currentUserId;
        _friendIds = List<String>.from(data['friendIds'] ?? []);
        _outgoingFriendRequests = List<String>.from(data['outgoingFriendRequests'] ?? []);
        _incomingFriendRequests = List<String>.from(data['incomingFriendRequests'] ?? []);
      });
    }
  }

  void _searchUsers() async {
    if (!_searchQuery.contains('#')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid friend tag (e.g., username#1234)')),
      );
      return;
    }

    final parts = _searchQuery.split('#');
    if (parts.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid friend tag format.')),
      );
      return;
    }

    String userName = parts[0].trim().toLowerCase();
    String friendCode = parts[1].trim();
    if (friendCode.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend code must be 4 digits.')),
      );
      return;
    }

    // Fetch users matching the search query
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('lowerCaseUserName', isEqualTo: userName)
        .where('friendCode', isEqualTo: friendCode)
        .get();

    List<User> users = snapshot.docs.map((doc) {
      final user = User.fromMap(doc.data() as Map<String, dynamic>);
      return user;
    }).where((user) => user.id != _currentUserId).toList(); // Exclude current user

    setState(() {
      _searchResults = users;
    });
  }

  void _sendFriendRequest(String receiverId) async {
    await _dbService.sendFriendRequest(_currentUserId, receiverId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Friend request sent')),
    );

    // Update the local state to reflect the sent request
    setState(() {
      _outgoingFriendRequests.add(receiverId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Friends')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Friend Tag (e.g., username#1234)'),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchUsers,
                ),
              ],
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty
                ? Center(
              child: Text(
                'Enter a friend tag to search.\nYou can find your own friend tag in your profile.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            )
                : _searchResults.isEmpty
                ? Center(
              child: Text(
                'No users found. Try another search.',
                style: const TextStyle(fontSize: 16),
              ),
            )
                : ListView(
              children: _searchResults.map((user) {
                Widget trailingWidget;

                if (user.id == _currentUserId) {
                  // Prevent adding yourself
                  trailingWidget = const Text('This is You');
                } else if (_friendIds.contains(user.id)) {
                  // Already friends
                  trailingWidget = const Text('Already Added');
                } else if (_outgoingFriendRequests.contains(user.id)) {
                  // Friend request already sent
                  trailingWidget = const Text('Request Sent');
                } else {
                  // Show Add Friend button
                  trailingWidget = ElevatedButton(
                    onPressed: () => _sendFriendRequest(user.id),
                    child: const Text('Add Friend'),
                  );
                }

                return ListTile(
                  title: Text(user.userName),
                  subtitle: Text('${user.userName}#${user.friendCode}'),
                  trailing: trailingWidget,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
