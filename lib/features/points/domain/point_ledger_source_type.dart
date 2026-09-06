enum PointLedgerSourceType { checkIn, missedCheckIn }

extension PointLedgerSourceTypeSemantics on PointLedgerSourceType {
  bool get isRedemption => switch (this) {
    PointLedgerSourceType.checkIn => false,
    PointLedgerSourceType.missedCheckIn => false,
  };
}
