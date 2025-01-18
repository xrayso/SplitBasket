import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/basket.dart';
import '../models/user.dart';
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

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Baskets'),
        actions: [
          // Profile Icon
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout
          ),
          IconButton(
            icon: Icon(Icons.person),
            onPressed: (){
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfileScreen()),
              );
            }
          ),
        ],
      ),
      body: FutureBuilder<User>(
        future: _dbService.getUserById(currentUserId),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          User currentUser = userSnapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Header
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Welcome, ${currentUser.userName}!',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              // Pending Invitations Badge
              StreamBuilder<List<Basket>>(
                stream: _dbService.getInvitedBaskets(currentUserId),
                builder: (context, snapshot) {
                  int invitationCount = 0;
                  if (snapshot.hasData) {
                    invitationCount = snapshot.data!.length;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  PendingInvitationsScreen()),
                        );
                      },
                      child: badges.Badge(
                        badgeColor: Colors.blue,
                        showBadge: invitationCount > 0,
                        position:
                        badges.BadgePosition.topEnd(top: 23, end: 145),
                        child: ListTile(
                          leading: Icon(Icons.group_add),
                          title: Text('Basket Invitations'),
                          trailing: Icon(Icons.arrow_forward_ios),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Baskets List
              Expanded(
                child: StreamBuilder<List<Basket>>(
                  stream: _dbService.getUserBaskets(currentUserId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    }

                    final baskets = snapshot.data!;
                    if (baskets.isEmpty) {
                      return Center(
                          child: Text('You are not part of any baskets.'));
                    }

                    return ListView.builder(
                      itemCount: baskets.length,
                      itemBuilder: (context, index) {
                        final basket = baskets[index];
                        return FutureBuilder<String>(
                          future: _getBasketHostFromId(basket.hostId),
                          builder: (context, userSnapshot) {
                            String hostName = 'Loading...';
                            if (userSnapshot.hasData) {
                              hostName = userSnapshot.data!;
                            }
                            return Card(
                              elevation: 2.0,
                              margin: EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              child: ListTile(
                                leading: Icon(
                                  Icons.shopping_basket,
                                  color: Theme.of(context).primaryColor,
                                ),
                                title: Text(basket.name),
                                subtitle: Text('Host: $hostName'),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          BasketScreen(
                                              basketId: basket.id),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showJoinBasketOptions,
        child: Icon(Icons.add),
      ),
    );
  }

  void _showJoinBasketOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          // Rounded corners for the modal
          decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16.0),
                topRight: Radius.circular(16.0)),
          ),
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.create),
                title: Text('Create New Basket'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => CreateBasketScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.input),
                title: Text('Join with Invitation Code'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => JoinBasketScreen()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _getBasketHostFromId (String id) async{
    if (id == _authService.currentUser!.uid) return "You";
    return await _dbService.getUserNameById(id);
  }

  void _logout() async {
    await _authService.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }
}
