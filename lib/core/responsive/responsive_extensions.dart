import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;

import 'screen_breakpoints.dart';

/// Extension on [BuildContext] for clean, concise responsive accessors.
extension ResponsiveContextX on BuildContext {
  /// Total screen width.
  ///
  /// [MediaQuery.sizeOf] rather than `MediaQuery.of(this).size`: the latter
  /// subscribes the caller to *every* MediaQuery field, so a widget asking only
  /// for a breakpoint also rebuilt on each frame of the keyboard slide (view
  /// insets), on orientation, on text-scale — none of which change the width.
  /// Every responsive getter below funnels through here, so this one line
  /// decides how often a large part of the app rebuilds.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Total screen height.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Active device category based on screen width.
  InoDeviceType get deviceType => ScreenBreakpoints.getDeviceType(screenWidth);

  /// Whether current screen is a small phone (< 360dp).
  bool get isMobileSmall => deviceType == InoDeviceType.mobileSmall;

  /// Whether current screen is a normal phone (360dp - 410dp).
  bool get isMobileNormal => deviceType == InoDeviceType.mobileNormal;

  /// Whether current screen is a large phone (411dp - 599dp).
  bool get isMobileLarge => deviceType == InoDeviceType.mobileLarge;

  /// Whether current screen is a tablet (>= 600dp).
  bool get isTablet => deviceType == InoDeviceType.tablet;

  /// Screen horizontal margin/padding tailored to active breakpoint.
  double get responsivePadding => ScreenBreakpoints.getScreenPadding(screenWidth);

  /// Column count for Quick Actions grid.
  int get quickActionsColumns => ScreenBreakpoints.getQuickActionsColumns(screenWidth);

  /// Column count for Property & Finance Tools grid.
  int get toolsColumns => ScreenBreakpoints.getToolsColumns(screenWidth);

  /// Column count for the full Property & Finance Tools hub screen.
  int get financeHubColumns =>
      ScreenBreakpoints.getFinanceHubColumns(screenWidth);

  /// Row height for finance hub list tiles (1-per-row on phones).
  double get financeHubRowHeight =>
      ScreenBreakpoints.getFinanceHubRowHeight(screenWidth);

  /// Child aspect ratio for Property & Finance Tools grid.
  double get toolsAspectRatio => ScreenBreakpoints.getToolsAspectRatio(screenWidth);

  /// True when My Vaults / Needs Attention should use a 2×2 grid.
  bool get useTwoByTwoIconGrid =>
      ScreenBreakpoints.useTwoByTwoIconGrid(screenWidth);

  /// Gap between home icon tiles.
  double get iconGridGap => ScreenBreakpoints.getIconGridGap(screenWidth);

  /// Notes grid columns.
  int get notesGridColumns => ScreenBreakpoints.getNotesGridColumns(screenWidth);

  /// Notes grid child aspect ratio.
  double get notesGridAspectRatio =>
      ScreenBreakpoints.getNotesGridAspectRatio(screenWidth);

  /// Share format / duration tile aspect ratio.
  double get shareTileAspectRatio =>
      ScreenBreakpoints.getShareTileAspectRatio(screenWidth);

  /// Wallet hub card minimum height.
  double get walletHubCardMinHeight =>
      ScreenBreakpoints.getWalletHubCardMinHeight(screenWidth);

  /// Horizontal carousel height from a design [base], scaled for width + text.
  double horizontalCardHeight(double base) =>
      ScreenBreakpoints.getHorizontalCardHeight(
        screenWidth,
        base: base,
        textScale: MediaQuery.textScalerOf(this).scale(1),
      );
}

/// Extension on [num] wrapping flutter_screenutil for type safety and brevity.
extension ResponsiveNumX on num {
  /// Responsive width scaled against 393dp reference.
  double get rw => w;

  /// Responsive height scaled against 852dp reference.
  double get rh => h;

  /// Responsive font size auto-scaled across displays.
  double get rsp => sp;

  /// Responsive corner radius.
  double get rr => r;
}
