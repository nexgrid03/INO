import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Thin wrapper around [SvgPicture.asset] with optional tinting.
///
/// Home launcher icons are single-color SVGs; pass [color] to recolor via
/// [BlendMode.srcIn]. Omit [color] to render the asset as authored.
class InoSvgIcon extends StatelessWidget {
  const InoSvgIcon(
    this.asset, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  /// Path under the project assets, e.g. `assets/icons/home/scan.svg`.
  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: semanticLabel,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

/// Bundled Home / launcher icon asset paths.
abstract final class InoHomeIcons {
  static const documents = 'assets/icons/home/documents.svg';
  static const notes = 'assets/icons/home/notes.svg';
  static const expenses = 'assets/icons/home/expenses.svg';
  static const scan = 'assets/icons/home/scan.svg';
  static const offline = 'assets/icons/home/offline.svg';
  static const reminder = 'assets/icons/home/reminder.svg';
  static const voice = 'assets/icons/home/voice.svg';
  static const netWorth = 'assets/icons/home/net_worth.svg';
  static const identity = 'assets/icons/home/identity.svg';
  static const property = 'assets/icons/home/property.svg';
  static const investments = 'assets/icons/home/investments.svg';
  static const cards = 'assets/icons/home/cards.svg';
  static const area = 'assets/icons/home/area.svg';
  static const emi = 'assets/icons/home/emi.svg';
  static const sip = 'assets/icons/home/sip.svg';
  static const stamp = 'assets/icons/home/stamp.svg';
  static const unit = 'assets/icons/home/unit.svg';
  static const tax = 'assets/icons/home/tax.svg';
}
