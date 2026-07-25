/// The property-area units the converter supports.
///
/// Ordered small → large so pickers and the summary grid read naturally.
/// Everything is defined relative to a single canonical base - **square feet** -
/// chosen so the India-specific units (Ankanam / Cent / Gunta / Marla / Kanal /
/// Katha / Acre) stay mathematically exact; only the metric units carry the
/// exact foot→metre factor (1 ft = 0.3048 m ⇒ 1 sq.ft = 0.09290304 sq.m, both
/// exact).
enum AreaUnit {
  squareFeet,
  squareYards,
  squareMetres,
  chatak,
  ankanam,
  marla,
  cents,
  katha,
  are,
  guntas,
  grounds,
  kanal,
  bigha,
  acres,
  hectares,
}

extension AreaUnitX on AreaUnit {
  /// How many **square feet** are in ONE of this unit. This is the whole
  /// conversion table; every conversion is `value * from.sqFt / to.sqFt`.
  ///
  /// Verified against the spec:
  ///   1 acre = 43560 sq.ft = 4840 sq.yd = 100 cents = 40 guntas = 4046.8564224 sq.m
  ///   1 gunta = 1089 sq.ft = 121 sq.yd = 0.025 acre
  ///   1 cent  = 435.6 sq.ft = 48.4 sq.yd
  ///   1 ankanam = 72 sq.ft
  ///   1 marla = 272.25 sq.ft (1/160 acre); 1 kanal = 20 marla = 5445 sq.ft
  ///   1 katha = 720 sq.ft (Bengal standard, 1/20 bigha); 1 chatak = 45 sq.ft
  ///   1 are = 100 sq.m; 1 hectare = 100 are
  double get squareFeetPerUnit {
    switch (this) {
      case AreaUnit.squareFeet:
        return 1;
      case AreaUnit.squareYards:
        return 9; // 1 sq.yd = 3ft × 3ft = 9 sq.ft
      case AreaUnit.squareMetres:
        return 10.763910416709722; // 1 / 0.09290304
      case AreaUnit.chatak:
        return 45; // 1/16 katha (Bengal)
      case AreaUnit.ankanam:
        return 72;
      case AreaUnit.marla:
        return 272.25; // 1/160 acre (standard marla)
      case AreaUnit.cents:
        return 435.6; // 1/100 acre
      case AreaUnit.katha:
        // Katha is REGIONAL and varies by state; this uses the Bengal standard
        // 1 katha = 720 sq.ft = 1/20 bigha, consistent with the bigha below.
        return 720;
      case AreaUnit.are:
        return 1076.3910416709722; // 100 sq.m
      case AreaUnit.guntas:
        return 1089; // 1/40 acre
      case AreaUnit.grounds:
        return 2400; // 1 ground = 2400 sq.ft (Tamil Nadu standard)
      case AreaUnit.kanal:
        return 5445; // 20 marlas = 1/8 acre
      case AreaUnit.bigha:
        // Bigha is REGIONAL and varies by state; this uses the common
        // 1 bigha = 1600 sq.yd = 14400 sq.ft standard (Bengal/Assam). Adjust
        // here if your region differs (e.g. 27000 sq.ft in parts of the north).
        return 14400;
      case AreaUnit.acres:
        return 43560;
      case AreaUnit.hectares:
        return 107639.10416709722; // 10000 sq.m
    }
  }

  /// Full, human-readable name.
  String get label {
    switch (this) {
      case AreaUnit.squareFeet:
        return 'Square Feet';
      case AreaUnit.squareYards:
        return 'Square Yards';
      case AreaUnit.squareMetres:
        return 'Square Metres';
      case AreaUnit.chatak:
        return 'Chatak';
      case AreaUnit.ankanam:
        return 'Ankanam';
      case AreaUnit.marla:
        return 'Marla';
      case AreaUnit.cents:
        return 'Cents';
      case AreaUnit.katha:
        return 'Katha';
      case AreaUnit.are:
        return 'Are';
      case AreaUnit.guntas:
        return 'Guntas';
      case AreaUnit.grounds:
        return 'Grounds';
      case AreaUnit.kanal:
        return 'Kanal';
      case AreaUnit.bigha:
        return 'Bigha';
      case AreaUnit.acres:
        return 'Acres';
      case AreaUnit.hectares:
        return 'Hectares';
    }
  }

  /// Compact label for grids, chips and results.
  String get shortLabel {
    switch (this) {
      case AreaUnit.squareFeet:
        return 'Sq.Ft';
      case AreaUnit.squareYards:
        return 'Sq.Yards';
      case AreaUnit.squareMetres:
        return 'Sq.M';
      case AreaUnit.chatak:
        return 'Chatak';
      case AreaUnit.ankanam:
        return 'Ankanam';
      case AreaUnit.marla:
        return 'Marla';
      case AreaUnit.cents:
        return 'Cents';
      case AreaUnit.katha:
        return 'Katha';
      case AreaUnit.are:
        return 'Are';
      case AreaUnit.guntas:
        return 'Guntas';
      case AreaUnit.grounds:
        return 'Grounds';
      case AreaUnit.kanal:
        return 'Kanal';
      case AreaUnit.bigha:
        return 'Bigha';
      case AreaUnit.acres:
        return 'Acres';
      case AreaUnit.hectares:
        return 'Hectares';
    }
  }

  /// A regional alias shown as a subtitle in pickers (e.g. Telugu "Gajam"),
  /// or null when there isn't one.
  String? get alias {
    switch (this) {
      case AreaUnit.squareYards:
        return 'Gajam';
      case AreaUnit.cents:
        return 'Shatak / Decimal';
      case AreaUnit.katha:
        return 'Cottah';
      case AreaUnit.grounds:
        return 'Manai';
      default:
        return null;
    }
  }
}
