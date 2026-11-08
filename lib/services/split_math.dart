// Share and charge calculations, kept free of Firestore so they can be unit
// tested.
//
// An item's userShares map looks like { uid: {'share': double, 'isManual': bool} }.
// "Manual" shares are percentages someone typed in; everyone else who opted in
// ("auto") splits whatever is left over equally.

import '../models/grocery_item.dart';

/// Sets one user's share, then rebalances the auto shares.
/// A manual share of 0 means "opt out" and removes the user.
Map<String, dynamic> withShare(
  Map<String, dynamic> userShares,
  String uid, {
  required double share,
  required bool isManual,
}) {
  final shares = Map<String, dynamic>.from(userShares);
  if (share == 0.0 && isManual) {
    shares.remove(uid);
  } else {
    shares[uid] = {'share': share, 'isManual': isManual};
  }
  return rebalanceAutoShares(shares);
}

/// Opts a user in as an auto share, keeping any manual share they already set.
Map<String, dynamic> withOptIn(Map<String, dynamic> userShares, String uid) {
  final existing = userShares[uid];
  if (existing is Map && existing['isManual'] == true &&
      ((existing['share'] ?? 0) as num) > 0) {
    return Map<String, dynamic>.from(userShares);
  }
  return withShare(userShares, uid, share: 0.0, isManual: false);
}

Map<String, dynamic> withOptOut(Map<String, dynamic> userShares, String uid) =>
    withShare(userShares, uid, share: 0.0, isManual: true);

/// Everyone in [uids] splits the item equally, replacing any existing shares.
Map<String, dynamic> evenShares(Iterable<String> uids) {
  final ids = uids.toSet();
  if (ids.isEmpty) return {};
  return {
    for (final uid in ids) uid: {'share': 1.0 / ids.length, 'isManual': false},
  };
}

/// Auto users split whatever the manual shares leave over.
Map<String, dynamic> rebalanceAutoShares(Map<String, dynamic> userShares) {
  final shares = Map<String, dynamic>.from(userShares);
  double totalManual = 0.0;
  final autoUsers = <String>[];

  shares.forEach((uid, data) {
    if (data is Map && data['isManual'] == true) {
      totalManual += ((data['share'] ?? 0.0) as num).toDouble();
    } else {
      autoUsers.add(uid);
    }
  });

  var leftover = 1.0 - totalManual;
  if (leftover < 0) leftover = 0.0;
  final each = autoUsers.isEmpty ? 0.0 : leftover / autoUsers.length;
  for (final uid in autoUsers) {
    shares[uid] = {'share': each, 'isManual': false};
  }
  return shares;
}

/// One amount someone owes the person who paid.
class ChargeLine {
  final String payerId; // owes the money
  final String payeeId; // paid at the store
  final double amount;
  final GroceryItem? item; // null for tax
  /// For tax lines: tax as a fraction of what the payer owes the payee.
  final double taxRate;

  ChargeLine({
    required this.payerId,
    required this.payeeId,
    required this.amount,
    this.item,
    this.taxRate = 0,
  });

  bool get isTax => item == null;
}

/// The sales tax on each item, in the same order as [items].
///
/// Each receipt's tax ([tripTax], by trip id) is split across that trip's
/// taxed items in proportion to their cost, so a Costco receipt's tax never
/// lands on Farm Boy groceries. [otherTax] (typed in by the host, or from
/// receipts imported before trips existed) goes on the items that didn't come
/// from a receipt, or on everything when they all did. Within each group,
/// only items marked taxed are charged, unless none are; then all are, as
/// baskets made with older versions of the app expect.
List<double> itemTaxes(
  List<GroceryItem> items,
  double otherTax, [
  Map<String, double> tripTax = const {},
]) {
  final taxes = List<double>.filled(items.length, 0);
  void spread(List<int> group, double amount) {
    if (amount <= 0 || group.isEmpty) return;
    final taxed = group.where((i) => items[i].taxable).toList();
    final base = taxed.isNotEmpty ? taxed : group;
    final cost = base.fold(0.0, (sum, i) => sum + items[i].total);
    if (cost <= 0) return;
    for (final i in base) {
      taxes[i] += amount * items[i].total / cost;
    }
  }

  final all = List<int>.generate(items.length, (i) => i);
  tripTax.forEach((tripId, amount) =>
      spread(all.where((i) => items[i].trip?.id == tripId).toList(), amount));
  final byHand = all.where((i) => items[i].trip == null).toList();
  spread(byHand.isNotEmpty ? byHand : all, otherTax);
  return taxes;
}

/// Works out who owes whom when a basket is finalized. Tax is split as
/// [itemTaxes] describes, then across each item's shares, so nobody pays tax
/// on untaxed groceries or on another trip's receipt.
List<ChargeLine> computeCharges(
  List<GroceryItem> items,
  double otherTax, [
  Map<String, double> tripTax = const {},
]) {
  final lines = <ChargeLine>[];
  final owed = <String, Map<String, double>>{};
  final taxOwed = <String, Map<String, double>>{};
  final taxes = itemTaxes(items, otherTax, tripTax);

  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final cost = item.total;
    final itemTax = taxes[index];

    item.userShares.forEach((uid, data) {
      if (uid == item.paidBy || data is! Map) return;
      final share = ((data['share'] ?? 0.0) as num).toDouble();
      if (share <= 0) return;

      final amount = cost * share;
      if (amount > 0) {
        lines.add(ChargeLine(
          payerId: uid,
          payeeId: item.paidBy,
          amount: amount,
          item: item,
        ));
      }
      final byPayee = owed.putIfAbsent(uid, () => {});
      byPayee[item.paidBy] = (byPayee[item.paidBy] ?? 0) + amount;
      final taxByPayee = taxOwed.putIfAbsent(uid, () => {});
      taxByPayee[item.paidBy] = (taxByPayee[item.paidBy] ?? 0) + itemTax * share;
    });
  }

  taxOwed.forEach((payer, byPayee) {
    byPayee.forEach((payee, tax) {
      if (tax <= 0) return;
      final subtotal = owed[payer]?[payee] ?? 0;
      lines.add(ChargeLine(
        payerId: payer,
        payeeId: payee,
        amount: tax,
        taxRate: subtotal > 0 ? tax / subtotal : 0,
      ));
    });
  });
  return lines;
}

/// What [uid] is paying for in total, before tax.
double shareTotalFor(String uid, List<GroceryItem> items) =>
    items.fold(0.0, (sum, i) => sum + i.total * i.shareOf(uid));

/// [uid]'s part of the tax, split the same way [computeCharges] splits it.
double taxShareFor(
  String uid,
  List<GroceryItem> items,
  double otherTax, [
  Map<String, double> tripTax = const {},
]) {
  final taxes = itemTaxes(items, otherTax, tripTax);
  var mine = 0.0;
  for (var i = 0; i < items.length; i++) {
    mine += taxes[i] * items[i].shareOf(uid);
  }
  return mine;
}

/// All the tax that will actually be charged: a receipt's tax only counts
/// while some of its items are still in the basket.
double totalTax(
  List<GroceryItem> items,
  double otherTax, [
  Map<String, double> tripTax = const {},
]) =>
    itemTaxes(items, otherTax, tripTax).fold(0.0, (sum, t) => sum + t);
