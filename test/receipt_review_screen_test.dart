import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:split_basket/screens/receipt_review_screen.dart';

List<ReceiptLine> sampleLines() => [
      ReceiptLine(description: 'Kirkland Organic Eggs', qty: 1, total: 9.49),
      ReceiptLine(description: 'Paper Towels', qty: 1, total: 24.99, taxable: true),
      ReceiptLine(description: 'Bananas', qty: 2, total: 3.98),
    ];

/// Opens the review screen from a button so the test can read what it returns.
Future<Future<ReceiptReviewResult?> Function()> pumpReview(
  WidgetTester tester,
  List<ReceiptLine> lines, {
  double tax = 0,
  double? subtotal,
}) async {
  ReceiptReviewResult? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          child: const Text('open'),
          onPressed: () async {
            result = await Navigator.push<ReceiptReviewResult>(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiptReviewScreen(
                  title: 'Costco',
                  lines: lines,
                  memberIds: const ['me', 'sam'],
                  names: const {'me': 'Josh Ossip', 'sam': 'Sam Lee'},
                  defaultPayer: 'me',
                  tax: tax,
                  receiptSubtotal: subtotal,
                ),
              ),
            );
          },
        ),
      ),
    ),
  ));
  return () async => result;
}

void main() {
  testWidgets('everyone is in by default and unticked lines are skipped',
      (tester) async {
    final lines = sampleLines();
    final getResult = await pumpReview(tester, lines, tax: 3.25);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Add 3 items'), findsOneWidget);
    expect(lines.every((l) => l.people.containsAll({'me', 'sam'})), isTrue);
    expect(find.widgetWithText(TextField, '3.25'), findsOneWidget);

    // Skip the bananas.
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Add 2 items'), findsOneWidget);

    await tester.tap(find.text('Add 2 items'));
    await tester.pumpAndSettle();
    final result = await getResult();
    expect(result!.lines.map((l) => l.description),
        ['Kirkland Organic Eggs', 'Paper Towels']);
    expect(result.payerId, 'me');
    expect(result.tax, 3.25);
  });

  testWidgets('split-all chips and per-person toggles', (tester) async {
    final lines = sampleLines();
    await pumpReview(tester, lines);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Josh only'));
    await tester.pumpAndSettle();
    expect(lines.every((l) => l.people.length == 1 && l.people.contains('me')),
        isTrue);

    // Add Sam back to the first item only.
    await tester.tap(find.widgetWithText(FilterChip, 'Sam').first);
    await tester.pumpAndSettle();
    expect(lines[0].people, {'me', 'sam'});
    expect(lines[1].people, {'me'});

    await tester.tap(find.text('Decide later'));
    await tester.pumpAndSettle();
    expect(lines.every((l) => l.people.isEmpty), isTrue);
    expect(find.textContaining('3 for later'), findsOneWidget);
  });

  testWidgets('warns when lines do not add up to the receipt', (tester) async {
    await pumpReview(tester, sampleLines(), subtotal: 50.00);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('add up to \$38.46'), findsOneWidget);
  });

  testWidgets('fits a small phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 667 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final lines = sampleLines()
      ..add(ReceiptLine(
          description: 'Kirkland Signature Extra Virgin Olive Oil 2 L',
          qty: 12,
          total: 1234.56));
    await pumpReview(tester, lines, tax: 12.5, subtotal: 1.0);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('no warning when they match', (tester) async {
    await pumpReview(tester, sampleLines(), subtotal: 38.46);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('add up to'), findsNothing);
  });

  testWidgets('shows what was printed and the discount taken off', (tester) async {
    await pumpReview(tester, [
      ReceiptLine(
        description: 'Lubriderm Unscented Lotion',
        receiptText: 'LUBRIDERM 2PK',
        qty: 1,
        total: 10.99,
        discount: 4,
        taxable: true,
      ),
      ReceiptLine(description: 'Bananas', receiptText: 'BANANAS', qty: 1, total: 1.99),
    ]);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(r'On receipt: LUBRIDERM 2PK · $4.00 off'), findsOneWidget);
    // Same name as printed and no discount: nothing to add.
    expect(find.textContaining('On receipt: BANANAS'), findsNothing);
  });
}
