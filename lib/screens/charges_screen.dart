import 'package:flutter/material.dart';
import 'package:split_basket/models/aggregated_resolution_request.dart';
import 'charges_detail_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/charges.dart';
import '../models/aggregated_charge.dart';
import 'package:badges/badges.dart' as badges;


class ChargesScreen extends StatefulWidget {
  const ChargesScreen({super.key});

  @override
  _ChargesScreenState createState() => _ChargesScreenState();
}


class _ChargesScreenState extends State<ChargesScreen> with SingleTickerProviderStateMixin{
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }


  void _resolveAllCharges(String otherUserId) async {
    final currentUserId = _authService.currentUser!.uid;
    await _dbService.resolveAllCharges(currentUserId, otherUserId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('All charges resolved.')),
    );
  }

  void _requestResolutionForAllCharges(String otherUserId) async {
    final currentUserId = _authService.currentUser!.uid;
    try {
      await _dbService.requestResolutionForAllCharges(
          currentUserId, otherUserId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resolution request sent.')),
      );
    }catch (e){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resolution request sent.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Charges'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(48.0),
          child: StreamBuilder<int>(
            stream: _dbService.getPendingRequestCount(currentUserId),
            builder: (context, snapshot) {
              int pendingCount = snapshot.data ?? 0;

              return TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'All Charges'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Pending Requests'),
                        if (pendingCount > 0) SizedBox(width: 4),
                        if (pendingCount > 0)
                          badges.Badge(
                            badgeContent: Text(
                              pendingCount > 9 ? '9+' : pendingCount.toString(),
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                            position: badges.BadgePosition.topEnd(top: -12, end: -20),
                            badgeColor: Colors.red,
                            child: SizedBox(width: 0, height: 0),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllCharges(currentUserId),
          _buildPendingRequests(currentUserId),
        ],
      ),
    );
  }

  Widget _buildAllCharges(String currentUserId) {
    return Scaffold(
      appBar: AppBar(title: Text('Your Charges')),
      body: StreamBuilder<List<AggregatedCharge>>(
        stream: _dbService.getUniqueCharges(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return Center(child: Text("You have no charges!"));
          }
          final charges = snapshot.data!;


          return ListView.builder(
            itemCount: charges.length,
            itemBuilder: (context, index) {
              AggregatedCharge aggregatedCharge = charges[index];
              String otherUserId = aggregatedCharge.otherUserId;
              double netAmount = aggregatedCharge.netAmount;
              bool isRequested = aggregatedCharge.requested;
              bool isPayee = netAmount < 0;

              Color? tileColor;
              if (isPayee) {
                tileColor = Colors.green[100]; // User is payee (owed money)
              } else {
                tileColor = Colors.red[100]; // User is payer (owes money)
              }
              if (netAmount == 0){
                tileColor = Colors.orange[200];
              }

              return FutureBuilder<String>(
                future: _dbService.getUserNameById(otherUserId),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return ListTile(title: Text('Loading...'));
                  }

                  String userName = userSnapshot.data!;
                  double amount = netAmount.abs();

                  return ListTile(
                    tileColor: tileColor,
                    title: Text(userName),
                    subtitle: Text(isPayee
                        ? '$userName owes you \$${amount.toStringAsFixed(2)}'
                        : 'You owe \$${amount.toStringAsFixed(2)}'),
                    trailing: isPayee
                        ? ElevatedButton(
                      onPressed: () => _resolveAllCharges(otherUserId),
                      child: Text('Resolve All'),
                    )
                        : ElevatedButton(
                      onPressed: isRequested ? null : () => _requestResolutionForAllCharges(otherUserId),
                      child: Text(isRequested ? 'Requested' : 'Resolve Request'),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ChargesDetailScreen(
                                otherUserId: otherUserId,
                                userName: userName,
                                currentUserId: currentUserId,
                              ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
  Widget _buildPendingRequests(String currentUserId) {
    return StreamBuilder<List<AggregatedResolutionRequest>>(
      stream: _dbService.getUniquePendingResolutionRequests(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('No pending requests.'));
        }

        // This is now a list of aggregated requests, each from a different user
        final requests = snapshot.data!;

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final aggregatedRequest = requests[index];
            String requesterName = "";
            return ListTile(
              tileColor: Colors.green[100],
              // Look up the requester's username
              title: FutureBuilder<String>(
                future: _dbService.getUserNameById(aggregatedRequest.requestedBy),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return Text("Requested by: Loading...");
                  } else if (userSnapshot.hasError) {
                    return Text("Requested by: <error>");
                  } else {
                    requesterName = userSnapshot.data ?? "Unknown";
                    return Text("Requested by: $requesterName");
                  }
                },
              ),
              // Show the total aggregated amount
              subtitle: Text(
                  "Amount Requested: \$"
                      "${aggregatedRequest.totalAmountRequested.toStringAsFixed(2)}"
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Accept all requests from this user
                  ElevatedButton(
                    onPressed: () => _acceptAllRequests(
                      currentUserId,
                      aggregatedRequest,
                    ),
                    child: Text('Accept'),
                  ),
                  SizedBox(width: 8),
                  // Decline all requests from this user
                  ElevatedButton(
                    onPressed: () => _declineAllRequests(
                      currentUserId,
                      aggregatedRequest,
                    ),
                    child: Text(
                      'Decline',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ChargesDetailScreen(
                          otherUserId: requests[index].requestedBy,
                          userName: requesterName,
                          currentUserId: currentUserId,
                        ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  void _acceptRequest(Charge charge) async {
    await _dbService.acceptChargeResolution(charge.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Charge accepted and resolved.')),
    );
  }

  Future<void> _acceptAllRequests(String currentUserId, AggregatedResolutionRequest request) async {
    // "Accept" means to resolve all requested charges where
    // payer == request.requestedBy, payee == currentUserId
    await _dbService.resolveCharges(currentUserId, request);
  }

  Future<void> _declineAllRequests(String currentUserId, AggregatedResolutionRequest request) async {
    await _dbService.declineRequests(currentUserId, request);
  }


  void _declineRequest(Charge charge) async {
    await _dbService.declineChargeResolution(charge.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Charge resolution declined.')),
    );
  }
}