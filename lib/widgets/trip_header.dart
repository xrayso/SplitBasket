import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/grocery_item.dart';
import '../services/trip_groups.dart';
import 'ui.dart';

/// One colour per trip, in the order the trips were added. Picked to stay
/// apart from each other and readable in light and dark mode.
const _tripColours = [
  Color(0xFF1E88E5), // blue
  Color(0xFFF57C00), // orange
  Color(0xFF8E24AA), // purple
  Color(0xFF43A047), // green
  Color(0xFFD81B60), // pink
  Color(0xFF00ACC1), // cyan
  Color(0xFF6D4C41), // brown
  Color(0xFF5C6BC0), // indigo
];

/// The colour for a group: its trip's, or grey for items added by hand.
Color tripColour(TripGroup group) => group.colorIndex == null
    ? const Color(0xFF78909C)
    : _tripColours[group.colorIndex! % _tripColours.length];

/// "Today", "Yesterday", "Thu, Oct 3", or "Oct 3, 2025" for another year.
String tripDateLabel(Trip trip, {DateTime? now}) {
  final day = trip.day;
  if (day == null) return '';
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(day.year, day.month, day.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return day.year == today.year
      ? DateFormat('EEE, MMM d').format(day)
      : DateFormat('MMM d, y').format(day);
}

/// The band above a trip's items: store, place, day and what the trip came to.
class TripHeader extends StatelessWidget {
  static const height = 64.0;

  final TripGroup group;

  /// How many of the trip's items are showing, when a filter hides some.
  final int shown;

  /// The receipt's tax, shown beside the item count when there is any.
  final double tax;

  const TripHeader(
      {super.key, required this.group, required this.shown, this.tax = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final colour = tripColour(group);
    final trip = group.trip;

    final title = trip == null
        ? 'Added by hand'
        : [trip.store, trip.place].where((s) => s.isNotEmpty).join(' · ');
    final count = shown == group.items.length
        ? '${group.items.length} ${group.items.length == 1 ? 'item' : 'items'}'
        : '$shown of ${group.items.length} items';
    final subtitle = [
      if (trip != null && tripDateLabel(trip).isNotEmpty) tripDateLabel(trip),
      count,
      if (tax >= 0.005) '${money(tax)} tax',
    ].join(' · ');

    // Opaque, so items scrolling underneath the pinned header don't show.
    final band = Color.alphaBlend(
        colour.withValues(alpha: dark ? 0.26 : 0.14), scheme.surface);
    final strong = Color.lerp(colour, scheme.onSurface, dark ? 0.35 : 0.2)!;

    return Semantics(
      header: true,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: band,
          border: Border(
            left: BorderSide(color: colour, width: 6),
            bottom: BorderSide(color: colour.withValues(alpha: 0.5)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
              child: Icon(
                trip == null ? Icons.edit_outlined : Icons.storefront_outlined,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700, color: strong),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              money(group.total),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: strong),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pins a [TripHeader] to the top while its trip's items scroll past, so it's
/// always clear which trip you're looking at.
class TripHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TripGroup group;
  final int shown;
  final double tax;

  TripHeaderDelegate(this.group, this.shown, [this.tax = 0]);

  @override
  double get minExtent => TripHeader.height;

  @override
  double get maxExtent => TripHeader.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      TripHeader(group: group, shown: shown, tax: tax);

  @override
  bool shouldRebuild(TripHeaderDelegate old) =>
      old.group != group || old.shown != shown || old.tax != tax;
}
