import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/screens/wallet/wallet_detail_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

/// Representative categories: Identity exercises the curated record path, the
/// others exercise the data-driven fallback (including the "Vault" naming
/// branch and a currency metric).
const _categories = <WalletCategory>[
  WalletCategory(
    name: 'Identity Wallet',
    icon: Icons.badge_rounded,
    contents: ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID'],
    metric: '5',
    metricLabel: 'documents',
    gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
  ),
  WalletCategory(
    name: 'Investment Wallet',
    icon: Icons.trending_up_rounded,
    contents: ['Gold', 'Stocks', 'Mutual Funds', 'Land'],
    metric: '₹48.6L',
    metricLabel: 'portfolio',
    gradient: [Color(0xFF34D399), Color(0xFF7DD3FC)],
  ),
  WalletCategory(
    name: 'Password Vault',
    icon: Icons.lock_rounded,
    contents: ['Website Credentials', 'Bank Credentials'],
    metric: '38',
    metricLabel: 'passwords',
    gradient: [Color(0xFF0EA5A5), Color(0xFF34D399)],
  ),
];

void main() {
  for (final category in _categories) {
    testWidgets('${category.name} opens its detail screen without exceptions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: WalletDetailScreen(category: category),
        ),
      );

      // Repo's 280ms delayed load + entrance animations.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1200));

      expect(tester.takeException(), isNull);
      expect(find.text(category.name), findsOneWidget);
    });
  }
}
