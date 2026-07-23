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

  /// Calculates child aspect ratio for finance tool grid tiles.
  /// Wider-than-tall so the tiles stay compact — no airy internal whitespace
  /// that would read as an extra gap below the section.
  static double getToolsAspectRatio(double width) {
    final type = getDeviceType(width);
    switch (type) {
      case InoDeviceType.mobileSmall:
        return 1.55;
      case InoDeviceType.mobileNormal:
        return 1.70;
      case InoDeviceType.mobileLarge:
        return 1.80;
      case InoDeviceType.tablet:
        return 1.95;
    }
  }
}
