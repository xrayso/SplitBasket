import 'dart:math';

import 'package:flutter/material.dart';
import 'package:split_basket/models/aggregated_resolution_request.dart';
import 'package:split_basket/services/notification_service.dart';
import '../models/user.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'charges_detail_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/aggregated_charge.dart';

class ChargesScreen extends StatefulWidget {
  const ChargesScreen({super.key});

  @override
  _ChargesScreenState createState() => _ChargesScreenState();
}

class _ChargesScreenState extends State<ChargesScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  late final String _uid = _authService.currentUser!.uid;
  // Created once, so switching tabs doesn't re-download everything.
  late final Stream<List<AggregatedCharge>> _balances =
      _dbService.getUniqueCharges(_uid);
  late final Stream<List<AggregatedResolutionRequest>> _requests =
      _dbService.getUniquePendingResolutionRequests(_uid);
  late final Stream<int> _requestCount = _dbService.getPendingRequestCount(_uid);

  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resolveAllCharges(String otherUserId, String name, double amount) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark ${money(amount)} as paid?'),
        content: Text("This clears everything $name owes you. You can't undo it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark as paid')),
        ],
      ),
    );
    if (ok != true) return;
    await _dbService.resolveAllCharges(_uid, otherUserId);
    _showSnack('Marked as paid');
  }

  Future<void> _clearDeletedUser(String otherUserId, double amount) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this balance?'),
        content: Text(
          "This person deleted their account, so they can't confirm payments. "
          "Clearing removes the ${money(amount)} from your balances. You can't undo it.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _dbService.clearChargesWith(_uid, otherUserId);
      _showSnack('Cleared');
    } catch (e) {
      _showSnack("Couldn't clear that: $e");
    }
  }

  Future<void> _requestResolutionForAllCharges(String otherUserId, String name) async {
    try {
      await _dbService.requestResolutionForAllCharges(_uid, otherUserId);
      _showSnack("Sent. $name just has to confirm they got it.");
    } catch (e) {
      _showSnack("Couldn't send that: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Charges'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Balances'),
            Tab(
              child: StreamBuilder<int>(
                stream: _requestCount,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Badge(
                    isLabelVisible: count > 0,
                    label: Text(count > 9 ? '9+' : '$count'),
                    offset: const Offset(14, -4),
                    child: const Text('Requests'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllCharges(),
          _buildPendingRequests(),
        ],
      ),
    );
  }

  Widget _buildAllCharges() {
    return StreamBuilder<List<AggregatedCharge>>(
      stream: _balances,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final charges = snapshot.data!;
        if (charges.isEmpty) {
          return const EmptyState(
            icon: Icons.celebration_outlined,
            title: "You're all settled up",
            message: 'When a basket is finalized, what you owe and are owed shows up here.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: charges.length,
          itemBuilder: (context, index) {
            final charge = charges[index];
            return FutureBuilder<String>(
              future: _dbService.getUserNameById(charge.otherUserId),
              builder: (context, nameSnapshot) =>
                  _balanceCard(charge, nameSnapshot.data ?? '…'),
            );
          },
        );
      },
    );
  }

  Widget _balanceCard(AggregatedCharge charge, String name) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final net = charge.netAmount;
    final amount = net.abs();
    final owedToMe = net < 0;
    final even = amount < 0.005;

    final Widget actions;
    if (even) {
      actions = const SizedBox.shrink();
    } else if (name == kDeletedUserName) {
      actions = Row(
        children: [
          Expanded(
            child: Text('They deleted their account', style: subtleText(context)),
          ),
          FilledButton.tonal(
            onPressed: () => _clearDeletedUser(charge.otherUserId, amount),
            child: const Text('Clear'),
          ),
        ],
      );
    } else if (owedToMe) {
      actions = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Remind'),
            onPressed: () => sendReminder(charge.otherUserId, money(amount)),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _resolveAllCharges(charge.otherUserId, name, amount),
            child: const Text('Mark as paid'),
          ),
        ],
      );
    } else if (charge.requested) {
      actions = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.hourglass_top, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Waiting for $name to confirm', style: subtleText(context)),
        ],
      );
    } else {
      actions = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.tonal(
            onPressed: () => _requestResolutionForAllCharges(charge.otherUserId, name),
            child: const Text('I paid'),
          ),
        ],
      );
    }

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChargesDetailScreen(
              otherUserId: charge.otherUserId,
              userName: name,
              currentUserId: _uid,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  PersonAvatar(name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          even ? "You're even" : (owedToMe ? 'Owes you' : 'You owe'),
                          style: subtleText(context),
                        ),
                      ],
                    ),
                  ),
                  if (!even)
                    Text(
                      money(amount),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: owedToMe ? colors.positive : colors.negative,
                      ),
                    ),
                  Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 6),
              actions,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRequests() {
    return StreamBuilder<List<AggregatedResolutionRequest>>(
      stream: _requests,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No requests',
            message: "When someone says they've paid you back, you'll confirm it here.",
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            return FutureBuilder<String>(
              future: _dbService.getUserNameById(request.requestedBy),
              builder: (context, nameSnapshot) =>
                  _requestCard(request, nameSnapshot.data ?? '…'),
            );
          },
        );
      },
    );
  }

  Widget _requestCard(AggregatedResolutionRequest request, String name) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChargesDetailScreen(
              otherUserId: request.requestedBy,
              userName: name,
              currentUserId: _uid,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  PersonAvatar(name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const TextSpan(text: ' says they paid you '),
                        TextSpan(
                          text: money(request.totalAmountRequested),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.of(context).positive,
                          ),
                        ),
                      ]),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _declineAllRequests(request),
                    child: const Text('Not yet'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _acceptAllRequests(request),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptAllRequests(AggregatedResolutionRequest request) async {
    await _dbService.resolveCharges(_uid, request.requestedBy);
    _showSnack('Confirmed and cleared');
  }

  Future<void> _declineAllRequests(AggregatedResolutionRequest request) async {
    await _dbService.declineRequests(_uid, request);
  }

  void sendReminder(String otherUserId, String costAsFixedString) async {
    String myUserName = await _dbService.getUserNameById(_authService.currentUser!.uid);
    User otherUser = await _dbService.getUserById(otherUserId);

      List<String> reminderTitles = [
        "You Broke?",
        "Don’t Make Me Chase You!",
        "Debt? What Debt? Oh, THIS Debt!",
        "The IRS Would Be Faster…",
        "Remember me?",
        "Oh, So We’re Just NOT Paying Anymore?",
        "Breaking News: You Still Owe Me Money!",
        "I’m Just a Simple Person… Who Wants My Money",
        "This Debt is Old Enough to Rent a Car",
        "The Money’s Not Gonna Pay Itself!",
        "Breaking News: You Still Haven’t Paid",
        "Is My Money in Witness Protection?",
        "This Isn’t a Joke… But Kinda Is",
      ];

      List<String> reminderBodies = [
        "Hey ${otherUser.userName}, I checked my wallet—it’s still light. Why? ‘Cause YOU still owe $costAsFixedString! Pay up before I start charging you in emotional distress! – $myUserName",
        "${otherUser.userName}, I ain't about to turn into a bounty hunter, but you still owe $costAsFixedString. Don’t make me pull out the receipts! Just pay it before I start telling stories about you! – $myUserName",
        "Hey ${otherUser.userName}, I don’t mean to bring up bad memories, but remember that $costAsFixedString? Still a thing. Still unpaid. Let’s change that before I start sending polite threats. – $myUserName",
        "Hey ${otherUser.userName}, you still owe $costAsFixedString. I’d report you to collections, but they’d probably just laugh. Save yourself—just pay. – $myUserName",
        "Yo ${otherUser.userName}, you still owe $costAsFixedString. I don’t wanna talk about this on stage… but I *will.* Pay up before you end up in my next comedy set! – $myUserName",
        "${otherUser.userName}, do I look like a bank? A charity? No? Then why is $costAsFixedString still outstanding? Pay up before I start charging you interest… in public shame. – $myUserName",
        "Hey ${otherUser.userName}, I was just wondering—did you declare bankruptcy? Are you on a secret government watchlist? No? THEN WHY IS MY $costAsFixedString STILL MISSING? Pay up. – $myUserName",
        "${otherUser.userName}, I see you liking posts, watching Netflix, living your best life. Meanwhile, my $costAsFixedString is out here GONE. Let’s fix that. – $myUserName",
        "Hey ${otherUser.userName}, imagine a world where $costAsFixedString magically paid itself. That world doesn’t exist. So… do your part. – $myUserName",
        "${otherUser.userName}, if you finally send that $costAsFixedString, I’ll nominate you for the 'Most Decent Human of the Year' award. Otherwise, I’m calling David Attenborough to narrate your downfall. – $myUserName",
        "Hey ${otherUser.userName}, I don’t ask for much. Just $costAsFixedString. That’s it! Not an arm, not a leg, just… the money you OWE ME. – $myUserName",
        "Hey ${otherUser.userName}, your unpaid $costAsFixedString has been around so long, it’s practically family now. But I’m not in the adoption business. Pay up. – $myUserName",
        "${otherUser.userName}, if corrupt politicians can pretend to pay their debts, surely you can settle this $costAsFixedString? Make the responsible choice… for once. – $myUserName",
        "Hey ${otherUser.userName}, I checked the stock market today. Nothing crashed. So… what’s stopping you from paying that $costAsFixedString? – $myUserName",
        "${otherUser.userName}, still no $costAsFixedString? You walking around like you’re debt-free? This is EMBARRASSING! Pay up before I send your name to the debt hall of fame. – $myUserName",
        "Hey ${otherUser.userName}, that $costAsFixedString is just sitting there, untouched. Lonely. Crying. How ‘bout you send it home? – $myUserName",
        "Hey ${otherUser.userName}, I was just thinking… my $costAsFixedString must be starring in a missing person’s documentary by now. Time to bring it back. – $myUserName",
        "Hey ${otherUser.userName}, I haven’t seen my $costAsFixedString in ages. I hope it’s doing well… but I’d rather have it back. Let’s make that happen. – $myUserName",
        "Hey ${otherUser.userName}, I wrote a song about you paying me $costAsFixedString. Just kidding. But I *will* if you don’t pay soon. – $myUserName",
        "Hey ${otherUser.userName}, guess what’s funnier than me waiting on $costAsFixedString? Nothing. That’s the joke. Pay up. – $myUserName"
      ];
    int randomIndex = Random().nextInt(reminderTitles.length);
    sendNotification(
        reminderTitles[randomIndex],
        reminderBodies[randomIndex],
        [otherUser.token]
    );
    _showSnack('Reminder sent to ${otherUser.userName}');
  }
}
