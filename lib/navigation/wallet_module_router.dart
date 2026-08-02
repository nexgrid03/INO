import 'package:flutter/material.dart';

import '../models/wallet_models.dart' show WalletCategory;
import '../screens/cards/cards_wallet_screen.dart';
import '../screens/investments/investment_wallet_screen.dart';
import '../screens/passwords/password_vault_screen.dart';
import '../screens/property/property_wallet_screen.dart';
import '../screens/wallet/wallet_detail_screen.dart';

/// Shared routing for vault modules — Home My Vaults and Vault tab stay in sync.
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
