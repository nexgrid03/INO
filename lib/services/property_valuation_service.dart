/// A profit/loss result for a property held from a purchase price.
class ProfitLoss {
  const ProfitLoss({
    required this.amount,
    required this.percent,
  });

  /// Current value − purchase price (negative = loss).
  final double amount;

  /// Change as a percentage of the purchase price.
  final double percent;

  bool get isProfit => amount >= 0;

  static const zero = ProfitLoss(amount: 0, percent: 0);
}

/// Property-value maths: area × rate, plus profit/loss against a purchase
/// price. Stateless service layer — the UI never multiplies inline.
class PropertyValuationService {
  const PropertyValuationService._();
  static const PropertyValuationService instance =
      PropertyValuationService._();

  /// Market value = area × rate-per-unit (both in the same unit). Guards input.
  double marketValue({required double area, required double ratePerUnit}) {
    if (area <= 0 || ratePerUnit <= 0) return 0;
    return area * ratePerUnit;
  }

  /// Profit/loss of [currentValue] against [purchasePrice].
  ProfitLoss profitLoss({
    required double purchasePrice,
    required double currentValue,
  }) {
    if (purchasePrice <= 0 && currentValue <= 0) return ProfitLoss.zero;
    final diff = currentValue - purchasePrice;
    final percent = purchasePrice > 0 ? diff / purchasePrice * 100 : 0.0;
    return ProfitLoss(amount: diff, percent: percent);
  }

  /// Estimated future value after compounding [currentValue] at
  /// [annualAppreciationPercent] for [years].
  double appreciatedValue({
    required double currentValue,
    required double annualAppreciationPercent,
    required int years,
  }) {
    if (currentValue <= 0 || years <= 0) return currentValue;
    final rate = annualAppreciationPercent / 100;
    var value = currentValue;
    for (var i = 0; i < years; i++) {
      value *= (1 + rate);
    }
    return value;
  }
}
