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

  final List<Widget> _screens = [
    HomeScreen(),
    FriendsListScreen(),
    ChargesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: StreamBuilder<int>(
        stream: _dbService.getPendingRequestCount(currentUserId),
        builder: (context, snapshot) {
          int pendingCount = snapshot.data ?? 0;

          return BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);
            },
            items: [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Baskets'),
              BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Friends'),

              BottomNavigationBarItem(
                icon: pendingCount > 0
                    ? badges.Badge(
                  badgeContent: Text(
                    pendingCount.toString(),
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
      ),
    );
  }
}
