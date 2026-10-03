import 'package:flutter/material.dart';

import 'colour-utility.dart';

/// "$12.34", or "-$4.00" for negative amounts.
String money(double amount) =>
    '${amount < 0 ? '-' : ''}\$${amount.abs().toStringAsFixed(2)}';

/// Up to two initials, e.g. "Jordan Lee" -> "JL".
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.take(2).map((p) => p.characters.first).join();
  return letters.isEmpty ? '?' : letters.toUpperCase();
}

/// A person's initials in a circle tinted with their own colour, readable in
/// light and dark mode.
class PersonAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const PersonAvatar({super.key, required this.name, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = colorForName(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color.alphaBlend(
        base.withValues(alpha: theme.brightness == Brightness.dark ? 0.28 : 0.18),
        theme.colorScheme.surface,
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w600,
          color: onColor(base, theme.brightness),
        ),
      ),
    );
  }
}

/// A friendly message for an empty list, with an optional button.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Small grey text under a heading, e.g. "3 people · 12 items".
TextStyle? subtleText(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
