import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;

import 'screen_breakpoints.dart';

/// Application-wide Responsive System Initializer.
///
/// Wraps [ScreenUtilInit] with standard reference canvas (393 x 852)
/// enabling adaptive screen utilities across all child screens.
class InoResponsiveInit extends StatelessWidget {
  const InoResponsiveInit({
    super.key,
    required this.child,
    this.designSize = const Size(393, 852),
  });

  final Widget child;
  final Size designSize;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, _) => child,
    );
  }
}

/// Adaptive LayoutBuilder widget that supplies constraints and resolved [InoDeviceType].
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(
    BuildContext context,
    BoxConstraints constraints,
    InoDeviceType deviceType,
  ) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final deviceType = ScreenBreakpoints.getDeviceType(width);
        return builder(context, constraints, deviceType);
      },
    );
  }
}

/// Resolves a value tailored to the active screen breakpoint.
T responsiveValue<T>(
  BuildContext context, {
  required T mobileSmall,
  T? mobileNormal,
  T? mobileLarge,
  T? tablet,
}) {
  final width = MediaQuery.of(context).size.width;
  final deviceType = ScreenBreakpoints.getDeviceType(width);
  switch (deviceType) {
    case InoDeviceType.mobileSmall:
      return mobileSmall;
    case InoDeviceType.mobileNormal:
      return mobileNormal ?? mobileSmall;
    case InoDeviceType.mobileLarge:
      return mobileLarge ?? mobileNormal ?? mobileSmall;
    case InoDeviceType.tablet:
      return tablet ?? mobileLarge ?? mobileNormal ?? mobileSmall;
  }
}
