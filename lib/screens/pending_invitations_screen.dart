import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/basket.dart';
import '../widgets/ui.dart';

class PendingInvitationsScreen extends StatelessWidget {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  PendingInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Basket Invitations'),
      ),
      body: StreamBuilder<List<Basket>>(
        stream: _dbService.getInvitedBaskets(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading invitations'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final baskets = snapshot.data!;
          if (baskets.isEmpty) {
            return const EmptyState(
              icon: Icons.mark_email_read_outlined,
              title: 'No invitations',
              message: "When a friend invites you to a basket, it'll show up here.",
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: baskets.length,
            itemBuilder: (context, index) {
              final basket = baskets[index];
              return FutureBuilder<String>(
                future: _dbService.getUserNameById(basket.hostId),
                builder: (context, snapshot) {
                  final hostName = snapshot.data ?? '…';
                  final scheme = Theme.of(context).colorScheme;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.shopping_basket,
                                    color: scheme.onPrimaryContainer),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(basket.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(fontWeight: FontWeight.w600)),
                                    Text('From $hostName', style: subtleText(context)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _declineInvitation(basket.id, currentUserId),
                                child: const Text('Decline'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () =>
                                    _acceptInvitation(basket.id, currentUserId),
                                child: const Text('Join'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _acceptInvitation(String basketId, String userId) async {
    await _dbService.acceptBasketInvitation(basketId, userId);
  }

  void _declineInvitation(String basketId, String userId) async {
    await _dbService.declineBasketInvitation(basketId, userId);
  }
}
