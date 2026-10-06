import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'basket_screen.dart';
import 'home_screen.dart';
import 'friends_list_screen.dart';
import 'charges_screen.dart';
import 'connections_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

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
  // Created once, so switching tabs doesn't re-subscribe (and blink the badges).
  late final Stream<int> _pendingCharges =
      _dbService.getPendingRequestCount(_authService.currentUser!.uid);
  late final Stream<int> _friendRequests =
      _dbService.getFriendRequestCount(_authService.currentUser!.uid);

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
    String memberToken = "";

    memberToken = await FirebaseMessaging.instance.getToken() ?? "";
    _dbService.setToken(_authService.currentUser!.uid, memberToken);
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
          const ConnectionsScreen(),
        ],
      ),
      bottomNavigationBar: StreamBuilder<int>(
        stream: _pendingCharges,
        builder: (context, snapshot) {
          final pendingChargesCount = snapshot.data ?? 0;

          return StreamBuilder<int>(
            stream: _friendRequests,
            builder: (context, friendSnapshot) {
              final friendRequestCount = friendSnapshot.data ?? 0;

              Widget withBadge(IconData icon, int count) => Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: Icon(icon),
                  );

              return NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  setState(() => _currentIndex = index);
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.shopping_basket_outlined),
                    selectedIcon: Icon(Icons.shopping_basket),
                    label: 'Baskets',
                  ),
                  NavigationDestination(
                    icon: withBadge(Icons.people_outline, friendRequestCount),
                    selectedIcon: withBadge(Icons.people, friendRequestCount),
                    label: 'Friends',
                  ),
                  NavigationDestination(
                    icon: withBadge(Icons.account_balance_wallet_outlined,
                        pendingChargesCount),
                    selectedIcon: withBadge(
                        Icons.account_balance_wallet, pendingChargesCount),
                    label: 'Charges',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.link_rounded),
                    label: 'Connections',
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
