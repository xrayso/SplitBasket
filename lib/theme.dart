import 'package:flutter/material.dart';

class AppThemes {
  static final lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSwatch(
      primarySwatch: Colors.teal,
      accentColor: Colors.orangeAccent,
    ),
    primaryColor: Colors.teal,
    fontFamily: 'Roboto',
    brightness: Brightness.light,
  );

  static final darkTheme = ThemeData(
    colorScheme: ColorScheme.dark(
      primary: Colors.teal,
      secondary: Colors.orangeAccent,
    ),
    fontFamily: 'Roboto',
    brightness: Brightness.dark,
  );
}
