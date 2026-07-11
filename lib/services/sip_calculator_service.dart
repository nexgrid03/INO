import 'dart:math' as math;

/// The result of a SIP projection.
class SipResult {
  const SipResult({
    required this.investedAmount,
    required this.estimatedReturns,
    required this.futureValue,
  });

  final double investedAmount;
  final double estimatedReturns;
  final double futureValue;

  static const zero =
      SipResult(investedAmount: 0, estimatedReturns: 0, futureValue: 0);
}

/// Monthly-SIP future-value maths (annuity-due). Stateless service layer.
class SipCalculatorService {
  const SipCalculatorService._();
  static const SipCalculatorService instance = SipCalculatorService._();

  /// FV = M · ((1+i)^n − 1)/i · (1+i), where M is the monthly investment, i the
  /// monthly return and n the number of months. Handles a 0% return
  /// (FV = M·n) and guards bad input.
  SipResult calculate({
    required double monthlyInvestment,
    required double annualReturnPercent,
    required int years,
  }) {
    final months = years * 12;
    if (monthlyInvestment <= 0 || months <= 0) return SipResult.zero;

    final i = annualReturnPercent / 12 / 100;
    final double futureValue;
    if (i == 0) {
      futureValue = monthlyInvestment * months;
    } else {
      final growth = math.pow(1 + i, months).toDouble();
      futureValue = monthlyInvestment * ((growth - 1) / i) * (1 + i);
    }

    final invested = monthlyInvestment * months;
    return SipResult(
      investedAmount: invested,
      estimatedReturns: futureValue - invested,
      futureValue: futureValue,
    );
  }
}
