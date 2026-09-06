enum PointLedgerSourceType { checkIn, missedCheckIn, rewardRedemption }

extension PointLedgerSourceTypeSemantics on PointLedgerSourceType {
  bool get isRedemption => switch (this) {
    PointLedgerSourceType.checkIn => false,
    PointLedgerSourceType.missedCheckIn => false,
    PointLedgerSourceType.rewardRedemption => true,
  };
}
