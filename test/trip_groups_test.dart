import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:split_basket/models/grocery_item.dart';
import 'package:split_basket/services/trip_groups.dart';
import 'package:split_basket/theme.dart';
import 'package:split_basket/widgets/trip_header.dart';

GroceryItem item(String name, double price, {Trip? trip}) => GroceryItem(
      id: name,
      name: name,
      price: price,
      quantity: 1,
      addedBy: 'a',
      paidBy: 'a',
      userShares: const {},
      trip: trip,
    );

const costco = Trip(
    id: 'costco:1', store: 'Costco', place: 'Kingston', date: '2026-10-03');
const farmBoy = Trip(id: 'scan:2', store: 'Farm Boy', date: '2026-10-09');
const loblaws = Trip(id: 'scan:3', store: 'Loblaws', date: '2026-10-03');

void main() {
  test('a basket with no trips stays a plain list', () {
    expect(groupByTrip([item('Milk', 4), item('Eggs', 5)]), isEmpty);
  });

  test('items from the same receipt group together, newest trip first', () {
    final groups = groupByTrip([
      item('OJ', 5, trip: costco),
      item('Eggs', 9, trip: costco),
      item('OJ', 6, trip: farmBoy),
    ]);
    expect(groups.map((g) => g.trip!.store), ['Farm Boy', 'Costco']);
    expect(groups[1].items.map((i) => i.name), ['OJ', 'Eggs']);
    expect(groups[1].total, 14);
  });

  test('items added by hand go last, under no trip', () {
    final groups = groupByTrip([
      item('Gum', 2),
      item('OJ', 5, trip: costco),
    ]);
    expect(groups.map((g) => g.trip), [costco, null]);
    expect(groups.last.colorIndex, isNull);
  });

  test('colours follow the order trips were added, not their date', () {
    final groups = groupByTrip([
      item('a', 1, trip: costco),
      item('b', 1, trip: farmBoy),
      item('c', 1, trip: loblaws),
    ]);
    final byStore = {for (final g in groups) g.trip!.store: g.colorIndex};
    expect(byStore, {'Costco': 0, 'Farm Boy': 1, 'Loblaws': 2});
    // Same day as Costco but added later, so it sits above it.
    expect(groups.map((g) => g.trip!.store), ['Farm Boy', 'Loblaws', 'Costco']);
  });

  test('a trip survives a round trip through Firestore maps', () {
    final back = GroceryItem.fromMap(item('OJ', 5, trip: costco).toMap());
    expect(back.trip!.id, 'costco:1');
    expect(back.trip!.place, 'Kingston');
    expect(back.trip!.day, DateTime(2026, 10, 3));
    // Items from before trips existed still load.
    expect(GroceryItem.fromMap(item('Old', 1).toMap()).trip, isNull);
    // And editing an item keeps its trip.
    expect(back.copyWith(name: 'Juice').trip!.id, 'costco:1');
  });

  test('dates read naturally', () {
    final now = DateTime(2026, 10, 9, 15);
    String label(String d) =>
        tripDateLabel(Trip(id: 'x', store: 's', date: d), now: now);
    expect(label('2026-10-09'), 'Today');
    expect(label('2026-10-08'), 'Yesterday');
    expect(label('2026-10-03'), 'Sat, Oct 3');
    expect(label('2025-12-24'), 'Dec 24, 2025');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('header fits a narrow phone in $mode', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final groups = groupByTrip([
        item('Gum', 2),
        item('OJ', 5,
            trip: const Trip(
                id: 'x',
                store: 'A Very Long Store Name Indeed',
                place: 'Some Long Warehouse Location',
                date: '2026-10-03')),
      ]);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Scaffold(
          body: Column(children: [
            for (final g in groups) TripHeader(group: g, shown: g.items.length),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Added by hand'), findsOneWidget);
      expect(find.text('\$5.00'), findsOneWidget);
    });
  }
}
