import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../widgets/ui.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

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

  void _searchUsersRelaxed(String partialName) async {
    // 1. Clean up the input
    final queryText = partialName.trim().toLowerCase();
    if (queryText.isEmpty) {
      // If there's nothing typed, you might want to clear results
      setState(() {
        _searchResults = [];
      });
      return;
    }

    // 2. Perform a range query for “starts with”
    //    we use "queryText + '\uf8ff'" to capture anything
    //    that starts with queryText.
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('lowerCaseUserName', isGreaterThanOrEqualTo: queryText)
        .where('lowerCaseUserName', isLessThanOrEqualTo: queryText + '\uf8ff')
        .limit(5) // Return only top 5 matches
        .get();

    // 3. Convert docs -> List<User>, excluding current user
    final users = snapshot.docs
        .map((doc) => User.fromMap(doc.data()))
        .where((user) => user.id != _currentUserId)
        .toList();

    // 4. Update state
    setState(() {
      _searchResults = users;
    });
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              autofocus: true,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Name or friend tag, e.g. sam#1234',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _searchUsersRelaxed(_searchQuery);
              },
              onSubmitted: (_) {
                if (_searchQuery.contains('#')) _searchUsers();
              },
            ),
          ),
          Expanded(
            child: _searchQuery.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.person_search_outlined,
                    title: 'Find your friends',
                    message: "Search by name, or type their friend tag. "
                        "Your own tag is in your profile.",
                  )
                : _searchResults.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off,
                        title: 'No one found',
                        message: 'Check the spelling, or ask for their friend tag.',
                      )
                    : ListView(
                        children: _searchResults.map((user) {
                          final Widget trailing;
                          if (_friendIds.contains(user.id)) {
                            trailing = Text('Friends', style: subtleText(context));
                          } else if (_outgoingFriendRequests.contains(user.id)) {
                            trailing = Text('Requested', style: subtleText(context));
                          } else if (_incomingFriendRequests.contains(user.id)) {
                            // They already asked: accept instead of asking back.
                            trailing = FilledButton.tonal(
                              onPressed: () async {
                                await _dbService.acceptFriendRequest(
                                    _currentUserId, user.id);
                                setState(() {
                                  _incomingFriendRequests.remove(user.id);
                                  _friendIds.add(user.id);
                                });
                              },
                              child: const Text('Accept'),
                            );
                          } else {
                            trailing = FilledButton.tonal(
                              onPressed: () => _sendFriendRequest(user.id),
                              child: const Text('Add'),
                            );
                          }
                          return ListTile(
                            leading: PersonAvatar(name: user.userName),
                            title: Text(user.userName),
                            subtitle: Text('${user.userName}#${user.friendCode}'),
                            trailing: trailing,
                          );
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }
}
