import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/data/wallet_detail_repository.dart';
import 'package:inoapp/models/wallet_detail_models.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/screens/wallet/wallet_detail_screen.dart';
import 'package:inoapp/theme/app_theme.dart';

const _identity = WalletCategory(
  name: 'Identity Wallet',
  icon: Icons.badge_rounded,
  contents: ['Aadhaar', 'PAN', 'Passport', 'Driving License', 'Voter ID'],
  metric: '5',
  metricLabel: 'documents',
  gradient: [Color(0xFF00A86B), Color(0xFF38BDF8)],
);

class FakeWalletDetailRepository implements WalletDetailRepository {
  List<DocumentRecord> records = [];

  @override
  Future<WalletDetailData> load(WalletCategory category) async {
    final active = records.where((r) => r.status == DocumentStatus.active).length;
    final expiring = records.where((r) => r.status == DocumentStatus.expiringSoon || r.status == DocumentStatus.expired).length;
    return WalletDetailData(
      walletName: category.name,
      subtitle: 'Subtitle',
      icon: category.icon,
      gradient: category.gradient,
      lastUpdatedLabel: records.isEmpty ? 'No documents yet' : 'Updated Today',
      overview: DetailOverview(
        totalRecords: records.length,
        activeRecords: active,
        expiringSoon: expiring,
        lastAccessed: records.isEmpty ? '-' : 'Today',
        storageUsedLabel: '4 MB',
        storageFraction: 0.1,
      ),
      records: records,
      recents: const [],
      insights: const [],
      security: const SecurityStatus(
        score: 100,
        vaultLocked: true,
        biometricEnabled: true,
        lastBackup: 'Synced',
        cloudSynced: true,
      ),
      storage: StorageAnalytics(
        totalFiles: records.length,
        usedLabel: '4 MB',
        availableLabel: '5 GB',
        usedFraction: 0.1,
        monthlyUploads: records.length,
        monthly: const [0, 0, 0, 0, 0, 0],
      ),
    );
  }

  @override
  void addRecord(String walletName, DocumentRecord record) {}
  @override
  void updateRecord(String walletName, DocumentRecord record) {}
  @override
  void deleteRecord(String walletName, String recordId) {}
  @override
  void deleteRecordLocal(String walletName, String recordId) {}
}

void main() {
  testWidgets('Wallet Detail renders the document-manager structure',
      (tester) async {
    // Wide (800 logical) so the fixed-height bottom nav lays out cleanly, tall
    // enough to build every sliver (incl. the off-screen document list).
    tester.view.physicalSize = const Size(2400, 9000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeRepo = FakeWalletDetailRepository();
    WalletDetailRepository.instance = fakeRepo;

    // Test Case 1: Empty Wallet
    fakeRepo.records = [];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const WalletDetailScreen(
          key: ValueKey('empty'),
          category: _identity,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(tester.takeException(), isNull);
    expect(find.text('Identity Wallet'), findsOneWidget);
    expect(find.text('No Documents Yet'), findsOneWidget); // Empty state title
    expect(find.text('Search documents'), findsNothing); // Hidden when empty

    // Test Case 2: Populated Wallet
    fakeRepo.records = [
      DocumentRecord(
        id: '1',
        name: 'Aadhaar Card',
        category: 'Identity',
        icon: Icons.badge_rounded,
        uploadedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: DocumentStatus.active,
      ),
    ];

    // Rebuild with a DIFFERENT key: the screen loads its records once, in
    // initState. Re-pumping an identical widget would reuse the same State and
    // silently keep the empty-wallet data from Test Case 1.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const WalletDetailScreen(
          key: ValueKey('populated'),
          category: _identity,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(tester.takeException(), isNull);
    expect(find.text('Identity Wallet'), findsOneWidget);
    expect(find.text('Search documents'), findsOneWidget); // sticky search
    expect(find.text('Protected'), findsOneWidget); // ✓ vault protected
    expect(find.text('View Vault'), findsNothing); // Removed from redesign
    expect(find.text('Documents'), findsWidgets);

    // Status filter chips
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('All'), findsWidgets);

    // Document list card is shown instead of empty state
    expect(find.text('Aadhaar Card'), findsOneWidget);
    expect(find.text('No Documents Yet'), findsNothing);

    // Removed dashboard sections must NOT be present.
    expect(find.text('Recently Accessed'), findsNothing);
    expect(find.textContaining('Storage'), findsNothing);
    expect(find.text('Security Center'), findsNothing);
  });
}
