enum PointLedgerSourceType { checkIn }

extension PointLedgerSourceTypeSemantics on PointLedgerSourceType {
  bool get isRedemption => switch (this) {
    PointLedgerSourceType.checkIn => false,
  };
}
