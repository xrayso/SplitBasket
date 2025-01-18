import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:split_basket/screens/login_screen.dart';
import 'package:split_basket/screens/register_screen.dart';
import 'package:split_basket/services/auth_service.dart';
import 'package:split_basket/services/notification_service.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Initialize Firebase and other necessary services

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async{
  print('Received background message: ${message.toMap()}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await initializeNotifications();
  await setupNotificationChannels();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Check if onboarding has been seen
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool seenOnboarding = prefs.getBool('seenOnboarding') ?? false;

  runApp(SplitBasketApp(seenOnboarding: seenOnboarding));
}

class SplitBasketApp extends StatelessWidget {
  final bool seenOnboarding;

  const SplitBasketApp({super.key, required this.seenOnboarding});

  @override
  Widget build(BuildContext context) {
    // Define your color scheme
    final ColorScheme colorScheme = ColorScheme.fromSwatch(
      primarySwatch: Colors.teal,
      accentColor: Colors.orangeAccent,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SplitBasket',
      theme: ThemeData(
        colorScheme: colorScheme,
        primaryColor: colorScheme.primary,
        // You can define other theme properties here
        fontFamily: 'Roboto',
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: Colors.teal,
          secondary: Colors.orangeAccent,
        ),
        fontFamily: 'Roboto',
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system, // Use system theme
      home: seenOnboarding ? AuthenticationWrapper() : OnboardingScreen(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
      },
    );
  }
}

class AuthenticationWrapper extends StatelessWidget {
  final AuthService _authService = AuthService();

  AuthenticationWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    if (_authService.currentUser != null) {
      return MainScreen();
    } else {
      return LoginScreen();
    }
  }
}
