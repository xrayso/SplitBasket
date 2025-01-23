import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'basket_screen.dart';
import 'home_screen.dart';
import 'friends_list_screen.dart';
import 'charges_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'package:badges/badges.dart' as badges;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();


class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

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
    _initializeFirebaseMessaging();
  }



  void _initializeFirebaseMessaging() async{
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    messaging.requestPermission();

    // This fires when a message is received in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showSnackbar(message.notification!.title, message.notification!.body);
        _showLocalNotification(message);
      }
    });

    // This fires when the user taps on a notification & your app is opened
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data.containsKey('basketId')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BasketScreen(basketId: message.data['basketId']),
          ),
        );
      }
    });
    String token = await messaging.getToken() ?? "";
    _dbService.setToken(_authService.currentUser!.uid, token);
  }

  // Show a quick snackbar in the UI
  void _showSnackbar(String? title, String? body) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title: $body')),
    );
  }

  /// Show a local notification using flutter_local_notifications,
  /// referencing our custom sound channel.
  void _showLocalNotification(RemoteMessage message) {
    // Title/body fallback if null
    String notiTitle = message.notification?.title ?? 'Basket Finalized!';
    String notiBody = message.notification?.body ?? 'Check your charges';
    String channelId = message.notification?.android?.channelId ?? "default_channel_id";

    flutterLocalNotificationsPlugin.show(
      0, // notification ID
      notiTitle,
      notiBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Notification Channel',
          playSound: false
        ),
      ),
      payload: message.data['basketId'], // optional
    );
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
          setState(() => _currentIndex = index);
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
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                items: [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.home),
                    label: 'Baskets',
                  ),
                  BottomNavigationBarItem(
                    icon: friendRequestCount > 0
                        ? badges.Badge(
                      badgeContent: Text(
                        friendRequestCount.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                      child: const Icon(Icons.people),
                    )
                        : const Icon(Icons.people),
                    label: 'Friends',
                  ),
                  BottomNavigationBarItem(
                    icon: pendingChargesCount > 0
                        ? badges.Badge(
                      badgeContent: Text(
                        pendingChargesCount.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                      child: const Icon(Icons.receipt),
                    )
                        : const Icon(Icons.receipt),
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
