import '../models/grocery_item.dart';

/// The items from one shopping trip, or the ones added by hand ([trip] null).
class TripGroup {
  final Trip? trip;
  final List<GroceryItem> items;

  /// Which colour the trip gets: the order trips first appeared in the basket,
  /// which never changes because items are only ever appended. Null for the
  /// items added by hand.
  final int? colorIndex;

  const TripGroup(this.trip, this.items, this.colorIndex);

  double get total => items.fold(0.0, (sum, i) => sum + i.total);
}

/// Splits a basket's items into trips, newest trip first, with anything added
/// by hand last. Returns an empty list when no item came from a trip, so a
/// basket of hand-added items stays a plain list.
List<TripGroup> groupByTrip(List<GroceryItem> items) {
  final byTrip = <String, List<GroceryItem>>{};
  final trips = <String, Trip>{};
  final byHand = <GroceryItem>[];
  for (final item in items) {
    final trip = item.trip;
    if (trip == null) {
      byHand.add(item);
      continue;
    }
    trips.putIfAbsent(trip.id, () => trip);
    byTrip.putIfAbsent(trip.id, () => []).add(item);
  }
  if (trips.isEmpty) return const [];

  final order = trips.keys.toList();
  final groups = [
    for (var i = 0; i < order.length; i++)
      TripGroup(trips[order[i]], byTrip[order[i]]!, i),
  ]..sort((a, b) {
      final byDate = b.trip!.date.compareTo(a.trip!.date);
      // Same day: the one added last goes first.
      return byDate != 0 ? byDate : b.colorIndex!.compareTo(a.colorIndex!);
    });
  if (byHand.isNotEmpty) groups.add(TripGroup(null, byHand, null));
  return groups;
}
