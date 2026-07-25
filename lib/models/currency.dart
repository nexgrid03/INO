/// World currencies for the Property & Finance tools.
///
/// One record per currency: ISO code, display symbol, English name, flag and
/// whether amounts group the Indian way (lakh/crore: 1,09,20,000) or the
/// western way (millions: 10,920,000). The South-Asian currencies keep the
/// Indian system; everything else groups in threes.
///
/// The active selection is a device preference (see `AppSettings.currency`),
/// so every calculator shows the same currency until the user changes it.
class Currency {
  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.flag,
    this.indianGrouping = false,
  });

  /// ISO 4217 code, e.g. `INR`.
  final String code;

  /// The prefix shown before amounts, e.g. `₹` / `$` / `RM`.
  final String symbol;

  /// English display name, e.g. `Indian Rupee`.
  final String name;

  /// Flag emoji for pickers.
  final String flag;

  /// Whether amounts use lakh/crore grouping instead of thousands.
  final bool indianGrouping;
}

/// The full currency registry, INR first (the app's home market), then the
/// global majors, then alphabetical-ish regional groups. All entries are active
/// ISO 4217 currencies.
class Currencies {
  const Currencies._();

  static const List<Currency> all = [
    // Home market first.
    Currency(code: 'INR', symbol: '₹', name: 'Indian Rupee', flag: '🇮🇳', indianGrouping: true),

    // Global majors.
    Currency(code: 'USD', symbol: r'$', name: 'US Dollar', flag: '🇺🇸'),
    Currency(code: 'EUR', symbol: '€', name: 'Euro', flag: '🇪🇺'),
    Currency(code: 'GBP', symbol: '£', name: 'British Pound', flag: '🇬🇧'),
    Currency(code: 'JPY', symbol: '¥', name: 'Japanese Yen', flag: '🇯🇵'),
    Currency(code: 'CNY', symbol: 'CN¥', name: 'Chinese Yuan', flag: '🇨🇳'),
    Currency(code: 'CHF', symbol: 'CHF', name: 'Swiss Franc', flag: '🇨🇭'),
    Currency(code: 'AUD', symbol: r'A$', name: 'Australian Dollar', flag: '🇦🇺'),
    Currency(code: 'CAD', symbol: r'C$', name: 'Canadian Dollar', flag: '🇨🇦'),
    Currency(code: 'NZD', symbol: r'NZ$', name: 'New Zealand Dollar', flag: '🇳🇿'),
    Currency(code: 'SGD', symbol: r'S$', name: 'Singapore Dollar', flag: '🇸🇬'),
    Currency(code: 'HKD', symbol: r'HK$', name: 'Hong Kong Dollar', flag: '🇭🇰'),

    // South Asia (Indian grouping).
    Currency(code: 'PKR', symbol: '₨', name: 'Pakistani Rupee', flag: '🇵🇰', indianGrouping: true),
    Currency(code: 'BDT', symbol: '৳', name: 'Bangladeshi Taka', flag: '🇧🇩', indianGrouping: true),
    Currency(code: 'LKR', symbol: 'Rs', name: 'Sri Lankan Rupee', flag: '🇱🇰', indianGrouping: true),
    Currency(code: 'NPR', symbol: 'Rs', name: 'Nepalese Rupee', flag: '🇳🇵', indianGrouping: true),
    Currency(code: 'BTN', symbol: 'Nu.', name: 'Bhutanese Ngultrum', flag: '🇧🇹', indianGrouping: true),
    Currency(code: 'MVR', symbol: 'Rf', name: 'Maldivian Rufiyaa', flag: '🇲🇻'),
    Currency(code: 'AFN', symbol: '؋', name: 'Afghan Afghani', flag: '🇦🇫'),

    // Gulf & Middle East.
    Currency(code: 'AED', symbol: 'AED', name: 'UAE Dirham', flag: '🇦🇪'),
    Currency(code: 'SAR', symbol: 'SR', name: 'Saudi Riyal', flag: '🇸🇦'),
    Currency(code: 'QAR', symbol: 'QR', name: 'Qatari Riyal', flag: '🇶🇦'),
    Currency(code: 'KWD', symbol: 'KD', name: 'Kuwaiti Dinar', flag: '🇰🇼'),
    Currency(code: 'BHD', symbol: 'BD', name: 'Bahraini Dinar', flag: '🇧🇭'),
    Currency(code: 'OMR', symbol: 'RO', name: 'Omani Rial', flag: '🇴🇲'),
    Currency(code: 'ILS', symbol: '₪', name: 'Israeli Shekel', flag: '🇮🇱'),
    Currency(code: 'JOD', symbol: 'JD', name: 'Jordanian Dinar', flag: '🇯🇴'),

    // Asia-Pacific.
    Currency(code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit', flag: '🇲🇾'),
    Currency(code: 'THB', symbol: '฿', name: 'Thai Baht', flag: '🇹🇭'),
    Currency(code: 'IDR', symbol: 'Rp', name: 'Indonesian Rupiah', flag: '🇮🇩'),
    Currency(code: 'PHP', symbol: '₱', name: 'Philippine Peso', flag: '🇵🇭'),
    Currency(code: 'VND', symbol: '₫', name: 'Vietnamese Dong', flag: '🇻🇳'),
    Currency(code: 'KRW', symbol: '₩', name: 'South Korean Won', flag: '🇰🇷'),
    Currency(code: 'TWD', symbol: r'NT$', name: 'New Taiwan Dollar', flag: '🇹🇼'),
    Currency(code: 'MMK', symbol: 'K', name: 'Myanmar Kyat', flag: '🇲🇲'),
    Currency(code: 'KHR', symbol: '៛', name: 'Cambodian Riel', flag: '🇰🇭'),
    Currency(code: 'LAK', symbol: '₭', name: 'Lao Kip', flag: '🇱🇦'),
    Currency(code: 'KZT', symbol: '₸', name: 'Kazakhstani Tenge', flag: '🇰🇿'),

    // Europe.
    Currency(code: 'SEK', symbol: 'kr', name: 'Swedish Krona', flag: '🇸🇪'),
    Currency(code: 'NOK', symbol: 'kr', name: 'Norwegian Krone', flag: '🇳🇴'),
    Currency(code: 'DKK', symbol: 'kr', name: 'Danish Krone', flag: '🇩🇰'),
    Currency(code: 'PLN', symbol: 'zł', name: 'Polish Zloty', flag: '🇵🇱'),
    Currency(code: 'CZK', symbol: 'Kč', name: 'Czech Koruna', flag: '🇨🇿'),
    Currency(code: 'HUF', symbol: 'Ft', name: 'Hungarian Forint', flag: '🇭🇺'),
    Currency(code: 'RON', symbol: 'lei', name: 'Romanian Leu', flag: '🇷🇴'),
    Currency(code: 'UAH', symbol: '₴', name: 'Ukrainian Hryvnia', flag: '🇺🇦'),
    Currency(code: 'RUB', symbol: '₽', name: 'Russian Ruble', flag: '🇷🇺'),
    Currency(code: 'TRY', symbol: '₺', name: 'Turkish Lira', flag: '🇹🇷'),

    // Americas.
    Currency(code: 'BRL', symbol: r'R$', name: 'Brazilian Real', flag: '🇧🇷'),
    Currency(code: 'MXN', symbol: r'MX$', name: 'Mexican Peso', flag: '🇲🇽'),
    Currency(code: 'ARS', symbol: r'AR$', name: 'Argentine Peso', flag: '🇦🇷'),
    Currency(code: 'CLP', symbol: r'CL$', name: 'Chilean Peso', flag: '🇨🇱'),
    Currency(code: 'COP', symbol: r'CO$', name: 'Colombian Peso', flag: '🇨🇴'),
    Currency(code: 'PEN', symbol: 'S/', name: 'Peruvian Sol', flag: '🇵🇪'),

    // Africa.
    Currency(code: 'ZAR', symbol: 'R', name: 'South African Rand', flag: '🇿🇦'),
    Currency(code: 'NGN', symbol: '₦', name: 'Nigerian Naira', flag: '🇳🇬'),
    Currency(code: 'EGP', symbol: 'E£', name: 'Egyptian Pound', flag: '🇪🇬'),
    Currency(code: 'KES', symbol: 'KSh', name: 'Kenyan Shilling', flag: '🇰🇪'),
    Currency(code: 'GHS', symbol: 'GH₵', name: 'Ghanaian Cedi', flag: '🇬🇭'),
    Currency(code: 'TZS', symbol: 'TSh', name: 'Tanzanian Shilling', flag: '🇹🇿'),
    Currency(code: 'UGX', symbol: 'USh', name: 'Ugandan Shilling', flag: '🇺🇬'),
    Currency(code: 'MAD', symbol: 'MAD', name: 'Moroccan Dirham', flag: '🇲🇦'),
    Currency(code: 'ETB', symbol: 'Br', name: 'Ethiopian Birr', flag: '🇪🇹'),
  ];

  /// The default when nothing is persisted yet.
  static const Currency fallback = Currency(
    code: 'INR',
    symbol: '₹',
    name: 'Indian Rupee',
    flag: '🇮🇳',
    indianGrouping: true,
  );

  /// Looks a currency up by ISO code; unknown/legacy codes fall back to INR so
  /// a stale preference can never crash a calculator.
  static Currency byCode(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return fallback;
  }
}
