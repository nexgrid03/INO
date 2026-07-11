import 'dart:math' as math;

/// The result of an EMI calculation.
class EmiResult {
  const EmiResult({
    required this.emi,
    required this.principal,
    required this.totalInterest,
    required this.totalPayment,
  });

  /// Equated monthly instalment.
  final double emi;
  final double principal;
  final double totalInterest;
  final double totalPayment;

  static const zero =
      EmiResult(emi: 0, principal: 0, totalInterest: 0, totalPayment: 0);
}

/// Standard reducing-balance EMI maths. Stateless service layer — no UI here.
class EmiCalculatorService {
  const EmiCalculatorService._();
  static const EmiCalculatorService instance = EmiCalculatorService._();

  /// EMI = P·r·(1+r)^n / ((1+r)^n − 1), where r is the monthly rate and n the
  /// number of months. Handles a 0% rate (EMI = P/n) and guards bad input.
  EmiResult calculate({
    required double principal,
    required double annualRatePercent,
    required int months,
  }) {
    if (principal <= 0 || months <= 0) return EmiResult.zero;

    final r = annualRatePercent / 12 / 100;
    final double emi;
    if (r == 0) {
      emi = principal / months;
    } else {
      final growth = math.pow(1 + r, months).toDouble();
      emi = principal * r * growth / (growth - 1);
    }

    final totalPayment = emi * months;
    return EmiResult(
      emi: emi,
      principal: principal,
      totalInterest: totalPayment - principal,
      totalPayment: totalPayment,
    );
  }
}
