import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:split_basket/screens/login_screen.dart';
import 'package:split_basket/screens/register_screen.dart';
import 'package:split_basket/services/auth_service.dart';
import 'package:split_basket/services/notification_service.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Initialize Firebase and other necessary services

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async{
  print('Received background message: ${message.toMap()}');
}

// Local testing: `flutter run --dart-define=USE_EMULATORS=true` talks to the
// Firebase emulators (firebase.emulators.json) instead of the real project.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (_useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
    FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
  }

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SplitBasket',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
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
