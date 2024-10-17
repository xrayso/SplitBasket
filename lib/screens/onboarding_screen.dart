import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatelessWidget {
  Future<void> _onIntroEnd(context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenOnboarding', true);
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(fontSize: 16.0);
    const pageDecoration = const PageDecoration(
      titleTextStyle:
      TextStyle(fontSize: 28.0, fontWeight: FontWeight.bold),
      bodyTextStyle: bodyStyle,
      pageColor: Colors.white,
      imagePadding: EdgeInsets.all(24.0),
    );

    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: "Welcome to SplitBasket",
          body: "Easily split grocery expenses with friends and family.",
          // image: Image.asset('assets/images/onboarding1.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Create Baskets",
          body: "Create baskets and add items to share.",
          // image: Image.asset('assets/images/onboarding2.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Invite Friends",
          body: "Invite friends to join and split costs.",
          // image: Image.asset('assets/images/onboarding3.png'),
          decoration: pageDecoration,
        ),
      ],
      onDone: () => _onIntroEnd(context),
      showSkipButton: true,
      skip: const Text("Skip"),
      next: const Icon(Icons.arrow_forward),
      done:
      const Text("Done", style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
