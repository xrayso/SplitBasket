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
    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive font sizes
    final titleFontSize = screenWidth * 0.08; // 8% of screen width
    final bodyFontSize = screenWidth * 0.045; // 4.5% of screen width

    final titleStyle = TextStyle(
      fontSize: titleFontSize,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );

    final bodyStyle = TextStyle(
      fontSize: bodyFontSize,
      color: Colors.white70,
    );

    PageDecoration getPageDecoration(Color backgroundColor) {
      return PageDecoration(
        titleTextStyle: titleStyle,
        bodyTextStyle: bodyStyle,
        bodyPadding: EdgeInsets.symmetric(horizontal: 20.0),
        imagePadding: EdgeInsets.only(top: 40.0),
        pageColor: backgroundColor,
        imageFlex: 2,
        bodyFlex: 1,
      );
    }

    return Scaffold(
      body: IntroductionScreen(
        pages: [
          PageViewModel(
            title: "Welcome to SplitBasket",
            body: "Easily split grocery expenses with friends and family.",
            image: Icon(
              Icons.shopping_cart,
              size: screenWidth * 0.5,
              color: Colors.white,
            ),
            decoration: getPageDecoration(Colors.blueAccent),
          ),
          PageViewModel(
            title: "Create Baskets",
            body: "Create baskets and add items to share.",
            image: Icon(
              Icons.add_shopping_cart,
              size: screenWidth * 0.5,
              color: Colors.white,
            ),
            decoration: getPageDecoration(Colors.deepPurpleAccent),
          ),
          PageViewModel(
            title: "Invite Friends",
            body: "Invite friends to join and split costs.",
            image: Icon(
              Icons.group_add,
              size: screenWidth * 0.5,
              color: Colors.white,
            ),
            decoration: getPageDecoration(Colors.teal),
          ),
        ],
        onDone: () => _onIntroEnd(context),
        showSkipButton: true,
        skip: Text("Skip", style: TextStyle(color: Colors.white)),
        next: Icon(Icons.arrow_forward, color: Colors.white),
        done: Text("Done", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        dotsDecorator: DotsDecorator(
          activeColor: Colors.white,
          color: Colors.white54,
          size: Size(10.0, 10.0),
          activeSize: Size(22.0, 10.0),
          activeShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25.0),
          ),
        ),
        globalBackgroundColor: Colors.black, // To ensure consistent background
        isProgressTap: false, // Avoids tapping on dots to move pages
        isProgress: true, // Adds the bottom progress bar
      ),
    );
  }
}
