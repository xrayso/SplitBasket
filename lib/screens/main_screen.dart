import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'friends_list_screen.dart';
import 'charges_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'package:badges/badges.dart' as badges;

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: [
          HomeScreen(),
          FriendsListScreen(),
          ChargesScreen(),
        ],
      ),
      bottomNavigationBar: StreamBuilder<int>(
        stream: _dbService.getPendingRequestCount(currentUserId),
        builder: (context, snapshot) {
          int pendingChargesCount = snapshot.data ?? 0;

          return StreamBuilder<int>(
            stream: _dbService.getFriendRequestCount(currentUserId),
            builder: (context, friendSnapshot) {
              int friendRequestCount = friendSnapshot.data ?? 0;

              return BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() => _currentIndex = index);
                  _pageController.animateToPage(
                    index,
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                items: [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home),
                    label: 'Baskets',
                  ),
                  BottomNavigationBarItem(
                    icon: friendRequestCount > 0
                        ? badges.Badge(
                      badgeContent: Text(
                        friendRequestCount.toString(),
                        style: TextStyle(color: Colors.white),
                      ),
                      child: Icon(Icons.people),
                    )
                        : Icon(Icons.people),
                    label: 'Friends',
                  ),
                  BottomNavigationBarItem(
                    icon: pendingChargesCount > 0
                        ? badges.Badge(
                      badgeContent: Text(
                        pendingChargesCount.toString(),
                        style: TextStyle(color: Colors.white),
                      ),
                      child: Icon(Icons.receipt),
                    )
                        : Icon(Icons.receipt),
                    label: 'Charges',
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
