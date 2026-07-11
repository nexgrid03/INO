/// The weight unit gold is entered in.
enum GoldWeightUnit { grams, tola }

extension GoldWeightUnitX on GoldWeightUnit {
  String get label => switch (this) {
        GoldWeightUnit.grams => 'Grams',
        GoldWeightUnit.tola => 'Tola',
      };

  /// Grams in one of this unit (1 tola = 11.6638 g).
  double get grams => switch (this) {
        GoldWeightUnit.grams => 1,
        GoldWeightUnit.tola => 11.6638,
      };
}

/// Gold purity (karat).
enum GoldPurity { k24, k22, k18 }

extension GoldPurityX on GoldPurity {
  String get label => switch (this) {
        GoldPurity.k24 => '24K',
        GoldPurity.k22 => '22K',
        GoldPurity.k18 => '18K',
      };

  /// Fraction of pure gold (24K = 1.0, 22K = 22/24, 18K = 18/24).
  double get factor => switch (this) {
        GoldPurity.k24 => 24 / 24,
        GoldPurity.k22 => 22 / 24,
        GoldPurity.k18 => 18 / 24,
      };
}

/// The result of a gold valuation.
class GoldValue {
  const GoldValue({
    required this.weightInGrams,
    required this.pricePerGram,
    required this.totalValue,
  });

  final double weightInGrams;

  /// Price per gram at the chosen purity (24K price × purity factor).
  final double pricePerGram;
  final double totalValue;

  static const zero =
      GoldValue(weightInGrams: 0, pricePerGram: 0, totalValue: 0);
}

/// Converts a gold weight + purity + 24K rate into a value. Stateless.
class GoldCalculatorService {
  const GoldCalculatorService._();
  static const GoldCalculatorService instance = GoldCalculatorService._();

  GoldValue calculate({
    required double weight,
    required GoldWeightUnit unit,
    required GoldPurity purity,
    required double pricePerGram24k,
  }) {
    if (weight <= 0 || pricePerGram24k <= 0) return GoldValue.zero;
    final grams = weight * unit.grams;
    final pricePerGram = pricePerGram24k * purity.factor;
    return GoldValue(
      weightInGrams: grams,
      pricePerGram: pricePerGram,
      totalValue: grams * pricePerGram,
    );
  }
}
