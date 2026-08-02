import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../common/ino_background.dart';
import 'divine_glass.dart';

/// Page chrome for Divine Glass (Launcher) feature screens: sky wash +
/// frosted Top App Bar (back + title) + scrollable body.
class DivineGlassPage extends StatelessWidget {
  const DivineGlassPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showBack = true,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: floatingActionButton,
      appBar: DivineGlassAppBar.asPreferredSize(
        context,
        title: title,
        centerTitle: false,
        onBack: showBack ? () => Navigator.of(context).maybePop() : null,
        actions: actions,
      ),
      body: InoBackground(
        sky: true,
        child: SafeArea(
          top: false,
          bottom: false,
          child: body,
        ),
      ),
    );
  }
}
