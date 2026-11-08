// Netting charges between two people, kept free of Firestore so it can be
// unit tested.
//
// Charges run both ways: Sam can owe you $20 while you owe Sam $15. People
// settle the difference ($5), so paying, confirming and clearing always work
// on everything between the two of them, never one direction alone.

import '../models/aggregated_charge.dart';
import '../models/aggregated_resolution_request.dart';
import '../models/charges.dart';

/// One balance per person [uid] has charges with. A positive netAmount means
/// [uid] owes them. [AggregatedCharge.requested] is true once [uid] has said
/// they paid every charge they owe that person.
List<AggregatedCharge> netBalances(List<Charge> charges, String uid) {
  final net = <String, double>{};
  final requested = <String, bool>{};
  for (final charge in charges) {
    if (charge.payerId == uid) {
      final other = charge.payeeId;
      net[other] = (net[other] ?? 0) + charge.amount;
      // Only what you owe can be marked as paid by you; what they owe you
      // doesn't decide whether you're waiting on them.
      requested[other] =
          charge.status == 'requested' && (requested[other] ?? true);
    } else if (charge.payeeId == uid) {
      final other = charge.payerId;
      net[other] = (net[other] ?? 0) - charge.amount;
    }
  }
  return [
    for (final e in net.entries)
      AggregatedCharge(
        otherUserId: e.key,
        netAmount: e.value,
        requested: requested[e.key] ?? false,
      ),
  ];
}

/// People who say they've paid [uid] back, with what they settled: the net
/// between the two of you, not just their side of it.
List<AggregatedResolutionRequest> paymentClaims(
    List<Charge> charges, String uid) {
  final claims = <String, AggregatedResolutionRequest>{};
  for (final charge in charges) {
    if (charge.payeeId != uid || charge.status != 'requested') continue;
    final requester = charge.requestedBy;
    if (requester.isEmpty || requester != charge.payerId) continue;
    claims
        .putIfAbsent(
            requester,
            () => AggregatedResolutionRequest(
                requestedBy: requester, totalAmountRequested: 0, chargeIds: []))
        .chargeIds
        .add(charge.id);
  }
  for (final balance in netBalances(charges, uid)) {
    final claim = claims[balance.otherUserId];
    // netAmount is what uid owes them, so they owe uid its negative.
    if (claim != null) claim.totalAmountRequested = -balance.netAmount;
  }
  return claims.values.where((c) => c.totalAmountRequested > 0.005).toList();
}
