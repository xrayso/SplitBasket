// Drives the app against the local emulators (seeded by
// functions/scripts/seed-emulator.js) through a basket with two shopping
// trips. Run with:
//
//   flutter test integration_test/trips_test.dart --dart-define=USE_EMULATORS=true
//
// Prints "SHOT <name>" and pauses at each screen worth looking at, so a
// script can take simulator screenshots.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:split_basket/main.dart' as app;

Future<void> settle(WidgetTester tester, [int seconds = 3]) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, 2);
  // ignore: avoid_print
  print('SHOT $name');
  await settle(tester, 4);
}

/// Pumps until [finder] shows up, or fails listing the text on screen.
Future<void> waitFor(WidgetTester tester, Finder finder,
    {int seconds = 30}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .take(30)
      .join(' | ');
  fail('Never found $finder. On screen: $texts');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a basket groups its items by trip', (tester) async {
    app.main();
    await waitFor(tester,
        find.textContaining(RegExp(r'Welcome|Your Baskets|Invite Friends')));
    await settle(tester, 2);

    // Onboarding and sign-in, when this simulator hasn't seen the app yet.
    for (final label in ['Skip', 'Done']) {
      if (find.text(label).evaluate().isNotEmpty) {
        await tester.tap(find.text(label).first);
        await settle(tester, 2);
      }
    }
    await waitFor(
        tester, find.textContaining(RegExp(r'Welcome back|Your Baskets')));
    if (find.text('Welcome back').evaluate().isNotEmpty) {
      await tester.enterText(
          find.byType(TextField).at(0), 'test-josh@splitbasket.test');
      await tester.enterText(find.byType(TextField).at(1), 'emulator-only-123');
      await tester.tap(find.text('Sign in'));
      await settle(tester, 5);
    }

    await waitFor(tester, find.text('Costco run'));
    await tester.tap(find.text('Costco run'));
    await settle(tester, 4);
    expect(find.text('Farm Boy'), findsOneWidget);
    await shot(tester, 'basket-top');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await shot(tester, 'basket-scrolled');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await shot(tester, 'basket-bottom');

    // Two items have no one yet, so finalizing explains why it can't.
    await tester.tap(find.text('Finalize'));
    await waitFor(tester, find.text("Can't finalize yet"));
    await tester.tap(find.text('OK'));
    await settle(tester, 1);

    // Split everything so the tax step shows, one field per receipt.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester, 1);
    await tester.tap(find.text('Split everything evenly'));
    await waitFor(tester, find.text('Split evenly'));
    await tester.tap(find.text('Split evenly'));
    await settle(tester, 3);
    await tester.tap(find.text('Finalize'));
    await waitFor(tester, find.text('Finalize Basket'));
    expect(find.textContaining('Costco'), findsWidgets);
    await shot(tester, 'finalize');
    await tester.tap(find.text('Cancel'));
    await settle(tester, 1);

    await tester.tap(find.text('Summary'));
    await shot(tester, 'summary');
  });
}
