import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:split_basket/screens/login_screen.dart';
import 'package:split_basket/screens/register_screen.dart';
import 'package:split_basket/services/auth_service.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Initialize Firebase and other necessary services
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Check if onboarding has been seen
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool seenOnboarding = prefs.getBool('seenOnboarding') ?? false;

  runApp(SplitBasketApp(seenOnboarding: seenOnboarding));
}

class SplitBasketApp extends StatelessWidget {
  final bool seenOnboarding;

  SplitBasketApp({required this.seenOnboarding});

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

  @override
  Widget build(BuildContext context) {
    if (_authService.currentUser != null) {
      return MainScreen();
    } else {
      return LoginScreen();
    }
  }
}
