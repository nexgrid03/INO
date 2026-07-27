import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/repositories/wallet_tables.dart';

/// [WalletTables.slugFor] is the client-side twin of the database's
/// `public.ino_wallet_slug()` (supabase/setup_wallet_tables.sql). The app writes
/// to whatever table that function created, so the two implementations must
/// agree on every input - a silent divergence means writes land in a table that
/// does not exist, or worse, the wrong one.
///
/// The expectations below are the values Postgres produces for the same inputs.
void main() {
  group('WalletTables.slugFor', () {
    test('maps every built-in wallet to its table', () {
      expect(WalletTables.slugFor('Identity Wallet'), 'w_identity_wallet');
      expect(WalletTables.slugFor('Document Wallet'), 'w_document_wallet');
      expect(WalletTables.slugFor('Property Wallet'), 'w_property_wallet');
      expect(WalletTables.slugFor('Insurance Wallet'), 'w_insurance_wallet');
      expect(WalletTables.slugFor('Health Wallet'), 'w_health_wallet');
      expect(WalletTables.slugFor('Investment Wallet'), 'w_investment_wallet');
      expect(WalletTables.slugFor('Banking Wallet'), 'w_banking_wallet');
      expect(WalletTables.slugFor('Cards Wallet'), 'w_cards_wallet');
      expect(WalletTables.slugFor('Password Vault'), 'w_password_vault');
    });

    test('maps the hidden share cache wallet', () {
      // Leading/trailing underscores are stripped, so the sentinel name
      // '__ino_share_cache__' lands on w_ino_share_cache - not w___ino_….
      expect(WalletTables.slugFor('__ino_share_cache__'), 'w_ino_share_cache');
    });

    test('collapses runs of non-alphanumerics to a single underscore', () {
      expect(WalletTables.slugFor('My  Pets'), 'w_my_pets');
      expect(WalletTables.slugFor('Kids & Family'), 'w_kids_family');
      expect(WalletTables.slugFor("Dad's Papers"), 'w_dad_s_papers');
      expect(WalletTables.slugFor('Travel-2026'), 'w_travel_2026');
    });

    test('is case- and whitespace-insensitive, matching wallet identity', () {
      // CustomWalletStore treats names case-insensitively (CustomWallet.id), so
      // these must resolve to one table rather than three.
      expect(WalletTables.slugFor('  Pets  '), 'w_pets');
      expect(WalletTables.slugFor('PETS'), 'w_pets');
      expect(WalletTables.slugFor('Pets'), 'w_pets');
    });

    test('drops characters Postgres would not keep', () {
      expect(WalletTables.slugFor('My Pets 🐾'), 'w_my_pets');
      expect(WalletTables.slugFor('Café'), 'w_caf');
    });

    test('caps the slug at 40 characters before the prefix', () {
      final long = 'a' * 60;
      expect(WalletTables.slugFor(long), 'w_${'a' * 40}');
      expect(WalletTables.slugFor(long).length, 42);
    });
  });
}
