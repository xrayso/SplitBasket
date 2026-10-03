import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/basket.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'basket_screen.dart';
import 'create_basket_screen.dart';
import 'pending_invitations_screen.dart';
import 'join_basket_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  late final String _uid = _authService.currentUser!.uid;
  // Created once, so rebuilding the screen doesn't re-download everything.
  late final Stream<List<Basket>> _baskets = _dbService.getUserBaskets(_uid);
  late final Stream<List<Basket>> _invitations = _dbService.getInvitedBaskets(_uid);

  String _myName = '';
  Map<String, String> _hostNames = {};

  @override
  void initState() {
    super.initState();
    _dbService.getUserNameById(_uid).then((name) {
      if (mounted) setState(() => _myName = name);
    });
  }

  void _loadHostNames(List<Basket> baskets) {
    final ids = baskets.map((b) => b.hostId).where((id) => id != _uid).toSet();
    if (ids.every(_hostNames.containsKey)) return;
    _dbService.getUserNames(ids).then((names) {
      if (mounted) setState(() => _hostNames = {..._hostNames, ...names});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Baskets'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: _myName.isEmpty
                ? const Icon(Icons.account_circle_outlined)
                : PersonAvatar(name: _myName, radius: 15),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Basket>>(
        stream: _baskets,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load your baskets",
              message: 'Check your connection and try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final baskets = snapshot.data!;
          _loadHostNames(baskets);

          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 96),
            children: [
              _invitationBanner(),
              if (baskets.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 64),
                  child: EmptyState(
                    icon: Icons.shopping_basket_outlined,
                    title: 'No baskets yet',
                    message: 'Start one for your next shop, or join a '
                        "friend's basket with their invite code.",
                    action: FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('New basket'),
                      onPressed: _showJoinBasketOptions,
                    ),
                  ),
                ),
              for (final basket in baskets) _basketCard(basket),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showJoinBasketOptions,
        icon: const Icon(Icons.add),
        label: const Text('New basket'),
      ),
    );
  }

  Widget _invitationBanner() {
    return StreamBuilder<List<Basket>>(
      stream: _invitations,
      builder: (context, snapshot) {
        final invites = snapshot.data ?? const [];
        if (invites.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Card(
          color: scheme.secondaryContainer,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: ListTile(
            leading: Icon(Icons.mark_email_unread_outlined,
                color: scheme.onSecondaryContainer),
            title: Text(
              invites.length == 1
                  ? "You're invited to ${invites.first.name}"
                  : 'You have ${invites.length} basket invitations',
              style: TextStyle(
                  color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
            ),
            subtitle: Text('Tap to join or decline',
                style: TextStyle(color: scheme.onSecondaryContainer)),
            trailing: Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PendingInvitationsScreen()),
            ),
          ),
        );
      },
    );
  }

  Widget _basketCard(Basket basket) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = basket.items.fold(0.0, (s, i) => s + i.total);
    final needs = basket.items.where((i) => i.needsSomeone).length;
    final host = basket.hostId == _uid
        ? 'You host'
        : 'Hosted by ${_hostNames[basket.hostId] ?? '…'}';
    final people = basket.memberIds.length;
    final items = basket.items.length;

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BasketScreen(basketId: basket.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.shopping_basket, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      basket.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$host · $people ${people == 1 ? 'person' : 'people'} · '
                      '$items ${items == 1 ? 'item' : 'items'}',
                      style: subtleText(context),
                    ),
                    if (needs > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$needs ${needs == 1 ? 'item needs' : 'items need'} someone',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.of(context).warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (items > 0) ...[
                const SizedBox(width: 12),
                Text(
                  money(total),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showJoinBasketOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_shopping_cart),
                title: const Text('Create a new basket'),
                subtitle: const Text("You'll be the host"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CreateBasketScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('Join with an invite code'),
                subtitle: const Text("From a friend's basket"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => JoinBasketScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
