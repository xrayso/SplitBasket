import 'package:flutter/material.dart';

/// Light and dark themes, both generated from the brand teal so every surface,
/// text and accent colour has proper contrast in either mode.
class AppTheme {
  static const seed = Color(0xFF009688); // Colors.teal

  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

    return base.copyWith(
      // Material's letter spacing is tuned for Roboto; with the iPhone's own
      // font it looks stretched.
      textTheme: _withoutLetterSpacing(base.textTheme),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(minimumSize: const Size(64, 48), shape: rounded),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      extensions: [AppColors.forBrightness(brightness)],
    );
  }

  static TextTheme _withoutLetterSpacing(TextTheme t) => t.copyWith(
        displayLarge: t.displayLarge?.copyWith(letterSpacing: 0),
        displayMedium: t.displayMedium?.copyWith(letterSpacing: 0),
        displaySmall: t.displaySmall?.copyWith(letterSpacing: 0),
        headlineLarge: t.headlineLarge?.copyWith(letterSpacing: 0),
        headlineMedium: t.headlineMedium?.copyWith(letterSpacing: 0),
        headlineSmall: t.headlineSmall?.copyWith(letterSpacing: 0),
        titleLarge: t.titleLarge?.copyWith(letterSpacing: 0),
        titleMedium: t.titleMedium?.copyWith(letterSpacing: 0),
        titleSmall: t.titleSmall?.copyWith(letterSpacing: 0),
        bodyLarge: t.bodyLarge?.copyWith(letterSpacing: 0),
        bodyMedium: t.bodyMedium?.copyWith(letterSpacing: 0),
        bodySmall: t.bodySmall?.copyWith(letterSpacing: 0),
        labelLarge: t.labelLarge?.copyWith(letterSpacing: 0),
        labelMedium: t.labelMedium?.copyWith(letterSpacing: 0),
        labelSmall: t.labelSmall?.copyWith(letterSpacing: 0),
      );
}

/// Colours with a meaning (money owed to you, money you owe, needs attention)
/// that stay readable in both light and dark mode.
class AppColors extends ThemeExtension<AppColors> {
  final Color positive; // owed to you, all claimed
  final Color negative; // you owe
  final Color warning; // needs someone

  const AppColors({
    required this.positive,
    required this.negative,
    required this.warning,
  });

  factory AppColors.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark
          ? const AppColors(
              positive: Color(0xFF7DD99A),
              negative: Color(0xFFFF9C8F),
              warning: Color(0xFFFFB86B),
            )
          : const AppColors(
              positive: Color(0xFF1E7B3C),
              negative: Color(0xFFC0362C),
              warning: Color(0xFFB85C00),
            );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      AppColors.forBrightness(Theme.of(context).brightness);

  @override
  AppColors copyWith({Color? positive, Color? negative, Color? warning}) =>
      AppColors(
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
        warning: warning ?? this.warning,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
