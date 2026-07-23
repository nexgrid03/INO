import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;

import 'screen_breakpoints.dart';

/// Extension on [BuildContext] for clean, concise responsive accessors.
extension ResponsiveContextX on BuildContext {
  /// Total screen width.
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Total screen height.
  double get screenHeight => MediaQuery.of(this).size.height;

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

  /// Child aspect ratio for Property & Finance Tools grid.
  double get toolsAspectRatio => ScreenBreakpoints.getToolsAspectRatio(screenWidth);
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
