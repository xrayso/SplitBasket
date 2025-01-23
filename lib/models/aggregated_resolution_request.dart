class AggregatedResolutionRequest {
  final String requestedBy;
  final List<String> chargeIds;
  late double totalAmountRequested;

  AggregatedResolutionRequest({
    required this.requestedBy,
    required this.totalAmountRequested,
    required this.chargeIds,
  });
}
