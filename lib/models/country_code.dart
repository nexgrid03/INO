class CountryCode {
  const CountryCode({
    required this.name,
    required this.dialCode,
    required this.flag,
  });

  final String name;
  final String dialCode; // e.g. "+91"
  final String flag; // emoji

  @override
  String toString() => '$flag $dialCode';
}

/// Common country dial codes (India as default).
const List<CountryCode> kCountryCodes = [
  CountryCode(name: 'India', dialCode: '+91', flag: '🇮🇳'),
  CountryCode(name: 'United States', dialCode: '+1', flag: '🇺🇸'),
  CountryCode(name: 'United Kingdom', dialCode: '+44', flag: '🇬🇧'),
  CountryCode(name: 'United Arab Emirates', dialCode: '+971', flag: '🇦🇪'),
  CountryCode(name: 'Singapore', dialCode: '+65', flag: '🇸🇬'),
  CountryCode(name: 'Australia', dialCode: '+61', flag: '🇦🇺'),
  CountryCode(name: 'Canada', dialCode: '+1', flag: '🇨🇦'),
  CountryCode(name: 'Germany', dialCode: '+49', flag: '🇩🇪'),
  CountryCode(name: 'France', dialCode: '+33', flag: '🇫🇷'),
  CountryCode(name: 'Saudi Arabia', dialCode: '+966', flag: '🇸🇦'),
  CountryCode(name: 'Qatar', dialCode: '+974', flag: '🇶🇦'),
  CountryCode(name: 'Nepal', dialCode: '+977', flag: '🇳🇵'),
  CountryCode(name: 'Sri Lanka', dialCode: '+94', flag: '🇱🇰'),
  CountryCode(name: 'Bangladesh', dialCode: '+880', flag: '🇧🇩'),
  CountryCode(name: 'Malaysia', dialCode: '+60', flag: '🇲🇾'),
  CountryCode(name: 'South Africa', dialCode: '+27', flag: '🇿🇦'),
  CountryCode(name: 'New Zealand', dialCode: '+64', flag: '🇳🇿'),
  CountryCode(name: 'Japan', dialCode: '+81', flag: '🇯🇵'),
];
