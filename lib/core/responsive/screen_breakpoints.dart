/// Screen device categories based on logical width (dp).
enum InoDeviceType {
  mobileSmall, // width < 360dp
  mobileNormal, // 360dp <= width < 411dp
  mobileLarge, // 411dp <= width < 600dp
  tablet, // width >= 600dp
}

/// Breakpoint thresholds and adaptive layout metrics for the INO Design System.
class ScreenBreakpoints {
  ScreenBreakpoints._();

  static const double mobileSmallMax = 359;
  static const double mobileNormalMax = 410;
  static const double mobileLargeMax = 599;
  static const double tabletMin = 600;

  /// Resolves the current [InoDeviceType] based on screen width.
  static InoDeviceType getDeviceType(double width) {
    if (width < 360) return InoDeviceType.mobileSmall;
    if (width < 411) return InoDeviceType.mobileNormal;
    if (width < 600) return InoDeviceType.mobileLarge;
    return InoDeviceType.tablet;
  }

  /// Calculates dynamic horizontal screen edge padding.
  static double getScreenPadding(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 14.0;
      case InoDeviceType.mobileNormal:
        return 16.0;
      case InoDeviceType.mobileLarge:
        return 20.0;
      case InoDeviceType.tablet:
        return 32.0;
    }
  }

  /// Calculates Quick Actions grid column count.
  /// Small: 4 per row, Normal/Large: 5 per row, Tablet: 6 per row.
  static int getQuickActionsColumns(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 4;
      case InoDeviceType.mobileNormal:
      case InoDeviceType.mobileLarge:
        return 5;
      case InoDeviceType.tablet:
        return 6;
    }
  }

  /// Calculates Property & Finance Tools grid column count.
  /// Small: 2 per row, Normal/Large: 3 per row, Tablet: 6 per row.
  static int getToolsColumns(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 2;
      case InoDeviceType.mobileNormal:
      case InoDeviceType.mobileLarge:
        return 3;
      case InoDeviceType.tablet:
        return 6;
    }
  }

  /// Home icon grids (My Vaults, Needs Attention): use a 2×2 layout whenever
  /// a 4-across row would crush labels like "Investments" on phones.
  static bool useTwoByTwoIconGrid(double width) => width < tabletMin;

  /// Horizontal gap between home icon tiles.
  static double getIconGridGap(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 8.0;
      case InoDeviceType.mobileNormal:
        return 10.0;
      case InoDeviceType.mobileLarge:
        return 12.0;
      case InoDeviceType.tablet:
        return 14.0;
    }
  }

  /// Calculates child aspect ratio for finance tool grid tiles.
  /// Wider-than-tall so the tiles stay compact - no airy internal whitespace
  /// that would read as an extra gap below the section.
  static double getToolsAspectRatio(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 1.35;
      case InoDeviceType.mobileNormal:
        return 1.45;
      case InoDeviceType.mobileLarge:
        return 1.55;
      case InoDeviceType.tablet:
        return 1.75;
    }
  }

  /// Notes grid column count (2 on phones, 3 on tablet).
  static int getNotesGridColumns(double width) {
    return width >= tabletMin ? 3 : 2;
  }

  /// Notes grid aspect (width/height). Taller cells on narrow phones so
  /// title + body + chip + date fit without overflow.
  static double getNotesGridAspectRatio(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 0.62;
      case InoDeviceType.mobileNormal:
        return 0.68;
      case InoDeviceType.mobileLarge:
        return 0.72;
      case InoDeviceType.tablet:
        return 0.85;
    }
  }

  /// Share settings / config tile aspect (width/height).
  static double getShareTileAspectRatio(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 1.25;
      case InoDeviceType.mobileNormal:
        return 1.4;
      case InoDeviceType.mobileLarge:
        return 1.55;
      case InoDeviceType.tablet:
        return 1.7;
    }
  }

  /// Minimum height for Wallet Hub cards (icon + title + metric).
  static double getWalletHubCardMinHeight(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 128.0;
      case InoDeviceType.mobileNormal:
        return 132.0;
      case InoDeviceType.mobileLarge:
        return 136.0;
      case InoDeviceType.tablet:
        return 144.0;
    }
  }

  /// Horizontal carousel card height: [base] bumped for small widths and
  /// accessibility text scale so Column children do not overflow.
  static double getHorizontalCardHeight(
    double width, {
    required double base,
    double textScale = 1.0,
  }) {
    final type = getDeviceType(width);
    final widthBump = switch (type) {
      InoDeviceType.mobileSmall => 12.0,
      InoDeviceType.mobileNormal => 6.0,
      InoDeviceType.mobileLarge => 0.0,
      InoDeviceType.tablet => 8.0,
    };
    final scale = textScale.clamp(1.0, 1.6);
    return base + widthBump + (base * (scale - 1.0) * 0.55);
  }

  /// Finance hub tool-card content minimum height (pad + badge + text budget).
  static double getFinanceToolCardMinHeight({
    required bool narrow,
    required bool launcher,
  }) {
    final pad = narrow ? 6.0 : 8.0;
    final badge = narrow ? 36.0 : (launcher ? 42.0 : 40.0);
    final gap = narrow ? 3.0 : 4.0;
    const textBudget = 28.0;
    return (pad * 2) + badge + gap + textBudget;
  }
}
