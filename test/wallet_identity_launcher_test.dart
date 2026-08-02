import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/core/responsive/responsive.dart';
import 'package:inoapp/models/user_profile.dart';
import 'package:inoapp/models/wallet_detail_models.dart';
import 'package:inoapp/models/wallet_models.dart';
import 'package:inoapp/screens/wallet/wallet_detail_screen.dart';
import 'package:inoapp/screens/wallet/wallet_screen.dart';
import 'package:inoapp/theme/app_theme.dart';
import 'package:inoapp/theme/theme_controller.dart';
import 'package:inoapp/theme/theme_style.dart';
import 'package:inoapp/widgets/common/liquid_glass.dart';
import 'package:inoapp/widgets/divine_glass/divine_glass.dart';
import 'package:inoapp/widgets/wallet_detail/document_card.dart';
import 'package:inoapp/widgets/wallet_detail/empty_state.dart';

void main() {
  final profile = UserProfile(
    id: '1',
    authUserId: 'a',
    fullName: 'Tanishq Sharma',
    email: 't@example.com',
    preferredLanguage: 'en',
    biometricEnabled: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final identity = WalletCategory(
    name: 'Identity Wallet',
    icon: Icons.badge_rounded,
    contents: const ['Aadhaar', 'PAN'],
    metric: '2',
    metricLabel: 'documents',
    gradient: const [Color(0xFF0EA5E9), Color(0xFF0EA5E9)],
  );

  Widget wrap(Widget child, {ThemeStyle style = ThemeStyle.classic}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: InoStyleScope(
        style: style,
        child: InoResponsiveInit(child: child),
      ),
    );
  }

  setUp(() {
    ThemeController.style.value = ThemeStyle.classic;
  });

  testWidgets('Launcher DocumentCard uses DivineGlassDocumentCard',
      (tester) async {
    final record = DocumentRecord(
      id: '1',
      name: 'Aadhaar Card',
      category: 'Identity',
      icon: Icons.badge_rounded,
      uploadedAt: DateTime(2021, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: DocumentStatus.active,
      recordNumber: '123456789012',
    );

    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: DocumentCard(
            record: record,
            onOpen: () {},
            onFavorite: () {},
            onMore: () {},
          ),
        ),
        style: ThemeStyle.launcher,
      ),
    );
    await tester.pump();

    expect(find.byType(DivineGlassDocumentCard), findsOneWidget);
    expect(find.byType(LiquidGlass), findsWidgets);
    expect(find.text('VALID'), findsOneWidget);
  });

  testWidgets('Classic DocumentCard does not use DivineGlassDocumentCard',
      (tester) async {
    final record = DocumentRecord(
      id: '1',
      name: 'Aadhaar Card',
      category: 'Identity',
      icon: Icons.badge_rounded,
      uploadedAt: DateTime(2021, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: DocumentStatus.active,
    );

    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: DocumentCard(
            record: record,
            onOpen: () {},
            onFavorite: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DivineGlassDocumentCard), findsNothing);
    expect(find.text('VALID'), findsNothing);
  });

  testWidgets('Launcher WalletEmptyState uses DivineGlassEmptyPanel',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: WalletEmptyState(
            title: 'No documents yet',
            subtitle: 'Start building your digital vault.',
            onScan: () {},
            onUpload: () {},
            onCreate: () {},
          ),
        ),
        style: ThemeStyle.launcher,
      ),
    );
    await tester.pump();

    expect(find.byType(DivineGlassEmptyPanel), findsOneWidget);
  });

  testWidgets('Launcher Wallet hub shows glassy My Wallets', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrap(WalletScreen(profile: profile), style: ThemeStyle.launcher),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('My Wallets'), findsOneWidget);
    expect(find.byType(LiquidGlass), findsWidgets);
  });

  testWidgets('Classic WalletDetailScreen builds without DivineGlass filter',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrap(WalletDetailScreen(category: identity)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DivineGlassFilterButton), findsNothing);
    expect(find.byType(DivineGlassDocumentCard), findsNothing);
  });
}
