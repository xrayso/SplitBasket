import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/basket.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'invite_friends_screen.dart';

class BasketMembersScreen extends StatefulWidget {
  final Basket basket;

  const BasketMembersScreen({Key? key, required this.basket}) : super(key: key);

  @override
  State<BasketMembersScreen> createState() => _BasketMembersScreenState();
}

class _BasketMembersScreenState extends State<BasketMembersScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  bool _isLoading = true;         // Track if data is loading
  List<User> _members = [];       // Store the list of members in state
  String _errorMessage = '';      // Track any error that might occur

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  /// Fetch the members from the database and update state.
  Future<void> _fetchMembers() async {
    try {
      List<User> members = [];
      for (String memberId in widget.basket.memberIds) {
        User member = await _dbService.getUserById(memberId);
        members.add(member);
      }
      // Ensure the host is at the top
      members.sort((a, b) {
        if (a.id == widget.basket.hostId) return -1;
        if (b.id == widget.basket.hostId) return 1;
        return 0;
      });

      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading members: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;
    final isHost = widget.basket.hostId == currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Basket Members'),
        actions: [
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: () => _inviteFriends(context),
          ),
          IconButton(
            icon: Icon(Icons.share),
            onPressed: () {
              Share.share(
                'Join my basket using this code: ${widget.basket.invitationCode}',
              );
            },
          )
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Text(_errorMessage))
          : ListView.builder(
        itemCount: _members.length,
        itemBuilder: (context, index) {
          final member = _members[index];
          // Check if current user has already sent a friend request
          // (i.e., user's ID is in this member's incoming requests).
          final sentFriendRequest =
          member.incomingFriendRequests.contains(currentUserId);

          return ListTile(
            leading: CircleAvatar(
              child: Text(
                member.userName.substring(0, 1).toUpperCase(),
              ),
            ),
            title: Text(member.userName),
            subtitle: Text(member.email),
            trailing: _buildTrailingActions(
              isHost: isHost,
              currentUserId: currentUserId,
              member: member,
              sentFriendRequest: sentFriendRequest,
            ),
          );
        },
      ),
    );
  }

  /// Builds the trailing widget for each ListTile (friend request & remove button).
  Widget? _buildTrailingActions({
    required bool isHost,
    required String currentUserId,
    required User member,
    required bool sentFriendRequest,
  }) {
    final bool isCurrentUserHost = isHost;
    final bool isMemberHost = member.id == widget.basket.hostId;
    final bool isAlreadyFriend = member.friendIds.contains(currentUserId);
    final bool isSelf = member.id == currentUserId;

    // 1. If user is host, member is not host, and not already friend
    if (isCurrentUserHost && !isMemberHost && !isAlreadyFriend) {
      return Row(
        mainAxisSize: MainAxisSize.min, // Ensures buttons are side by side
        children: [
          IconButton(
            icon: Icon(
              Icons.person_add,
              color: sentFriendRequest ? Colors.green[100] : Colors.green,
            ),
            disabledColor: Colors.green[100], // color if onPressed is null
            onPressed: !sentFriendRequest
                ? () async {
              await _dbService.sendFriendRequest(currentUserId, member.id);
              setState(() {
                // Reflect change immediately in local data
                member.incomingFriendRequests.add(currentUserId);
              });
            }
                : null,
          ),
          IconButton(
            icon: Icon(Icons.remove_circle, color: Colors.red),
            onPressed: () => _removeMember(member.id),
          ),
        ],
      );
    }

    // 2. If not already friends, not the current user, show single friend request button
    if (!isAlreadyFriend && !isSelf) {
      return IconButton(
        icon: Icon(
          Icons.person_add,
          color: sentFriendRequest ? Colors.green[100] : Colors.green,
        ),
        disabledColor: Colors.green[100],
        onPressed: !sentFriendRequest
            ? () async {
          await _dbService.sendFriendRequest(currentUserId, member.id);
          setState(() {
            member.incomingFriendRequests.add(currentUserId);
          });
        }
            : null,
      );
    }

    // 3. Otherwise, show nothing
    return null;
  }

  Future<void> _inviteFriends(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InviteFriendsScreen(basketId: widget.basket.id),
      ),
    );
  }

  Future<void> _removeMember(String memberId) async {
    // Remove from local state first to reflect change immediately
    setState(() {
      _members.removeWhere((m) => m.id == memberId);
    });
    // Update the database
    widget.basket.memberIds.remove(memberId);
    await _dbService.updateBasketMembers(widget.basket.id, widget.basket.memberIds);
  }
}
