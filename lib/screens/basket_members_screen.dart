import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/basket.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/ui.dart';
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

  @override
  void didUpdateWidget(BasketMembersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.basket.memberIds.toSet();
    final now = widget.basket.memberIds.toSet();
    if (before.length != now.length || !before.containsAll(now)) _fetchMembers();
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
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Invite friends',
            onPressed: () => _inviteFriends(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _inviteCard(context),
                    for (final member in _members)
                      ListTile(
                        leading: PersonAvatar(name: member.userName),
                        title: Text(
                          member.id == currentUserId
                              ? '${member.userName} (you)'
                              : member.userName,
                        ),
                        subtitle: Text(
                          member.id == widget.basket.hostId
                              ? 'Host'
                              : '${member.userName}#${member.friendCode}',
                        ),
                        trailing: _buildTrailingActions(
                          isHost: isHost,
                          currentUserId: currentUserId,
                          member: member,
                          sentFriendRequest:
                              member.incomingFriendRequests.contains(currentUserId),
                        ),
                      ),
                  ],
                ),
    );
  }

  /// The basket's invite code, ready to copy or share.
  Widget _inviteCard(BuildContext context) {
    final theme = Theme.of(context);
    final code = widget.basket.invitationCode;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invite code', style: subtleText(context)),
                  const SizedBox(height: 2),
                  SelectableText(
                    code,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite code copied')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share code',
              onPressed: () => Share.share(
                'Join my basket "${widget.basket.name}" on SplitBasket with '
                'the code $code',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Friend request and remove buttons for a member's row.
  Widget? _buildTrailingActions({
    required bool isHost,
    required String currentUserId,
    required User member,
    required bool sentFriendRequest,
  }) {
    final isMemberHost = member.id == widget.basket.hostId;
    final isAlreadyFriend = member.friendIds.contains(currentUserId);
    final isSelf = member.id == currentUserId;

    final actions = <Widget>[
      if (!isAlreadyFriend && !isSelf)
        sentFriendRequest
            ? const Tooltip(
                message: 'Friend request sent',
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.how_to_reg_outlined),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                tooltip: 'Add friend',
                onPressed: () async {
                  await _dbService.sendFriendRequest(currentUserId, member.id);
                  setState(() => member.incomingFriendRequests.add(currentUserId));
                },
              ),
      if (isHost && !isMemberHost)
        IconButton(
          icon: Icon(Icons.person_remove_outlined,
              color: Theme.of(context).colorScheme.error),
          tooltip: 'Remove from basket',
          onPressed: () => _confirmRemove(member),
        ),
    ];
    if (actions.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  Future<void> _confirmRemove(User member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${member.userName}?'),
        content: const Text(
            "They'll no longer see this basket. Items they're in on keep their shares."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _removeMember(member.id);
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
