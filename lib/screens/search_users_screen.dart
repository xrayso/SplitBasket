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

  void _searchUsers() async {
    if (_searchQuery.length < 5) return;
    String userName = _searchQuery.substring(0, _searchQuery.length - 5);
    String friendCode = _searchQuery.substring(_searchQuery.length - 4, _searchQuery.length);
    final String currentUserName = await _dbService.getUserNameById(_authService.currentUser!.uid);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('userName', isEqualTo: userName)
        .where('userName', isNotEqualTo: currentUserName)
        .where('friendCode', isEqualTo: friendCode)
        .get();

    List<User> users = snapshot.docs.map((doc) {
      return User.fromMap(doc.data() as Map<String, dynamic>);
    }).toList();

    setState(() {
      _searchResults = users;
    });
  }

  void _sendFriendRequest(String receiverId) async {
    await _dbService.sendFriendRequest(_authService.currentUser!.uid, receiverId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Friend request sent')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add Friends')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(labelText: 'Friend Tag'),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.search),
                  onPressed: _searchUsers,
                ),
              ],
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty
                ? Center(
              child: Text(
                'Enter a friend tag to search.\nYou can find your own username tag in your profile.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            )
                : _searchResults.isEmpty
                ? Center(
              child: Text(
                'No users found. Try another search.',
                style: TextStyle(fontSize: 16),
              ),
            )
                : ListView(
              children: _searchResults.map((user) {
                return ListTile(
                  title: Text(user.userName),
                  subtitle: Text(user.email),
                  trailing: ElevatedButton(
                    onPressed: () => _sendFriendRequest(user.id),
                    child: Text('Add Friend'),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
