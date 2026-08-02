import 'package:flutter/material.dart';

import '../models/wallet_models.dart' show WalletCategory;
import '../screens/cards/cards_wallet_screen.dart';
import '../screens/investments/investment_wallet_screen.dart';
import '../screens/passwords/password_vault_screen.dart';
import '../screens/property/property_wallet_screen.dart';
import '../screens/wallet/wallet_detail_screen.dart';

/// Shared routing for vault modules — Home My Vaults and Vault tab stay in sync.
///
/// Module wallets (Property / Investment / Banking / Password) keep their own
/// registers; every **document** manager — including the folder action on those
/// modules — uses [WalletDetailScreen] so upload/list chrome stays identical.
Widget walletScreenFor(WalletCategory category) {
  switch (category.name) {
    case 'Property Wallet':
      return PropertyWalletScreen(category: category);
    case 'Investment Wallet':
      return InvestmentWalletScreen(category: category);
    case 'Banking Wallet':
      return CardsWalletScreen(category: category);
    case 'Password Vault':
      return PasswordVaultScreen(category: category);
    default:
      return WalletDetailScreen(category: category);
  }
}

/// Opens the shared document shell for [category] (same UI for every wallet).
Future<void> openWalletDocuments(
  BuildContext context,
  WalletCategory category,
) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WalletDetailScreen(category: category),
    ),
  );
}
