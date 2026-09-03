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

  /// Home My Vaults SVG for a built-in wallet name, or null.
  static String? vaultSvg(String walletName) => switch (walletName) {
        'Identity Wallet' => identity,
        'Property Wallet' => property,
        'Investment Wallet' => investments,
        'Banking Wallet' => cards,
        _ => null,
      };

  /// Home finance-tool SVG for a tool id, or null.
  static String? financeSvg(String toolId) => switch (toolId) {
        'area' => area,
        'emi' => emi,
        'sip' => sip,
        'stamp' || 'valuation' => stamp,
        'unit' => unit,
        'tax' || 'fx' || 'gold' => tax,
        _ => null,
      };
}

/// Soft-3D PNG icons for Home assets.
///
/// Full circular discs for Quick Actions; coloured glyphs for vault / strip /
/// finance tiles (tile chrome + count badge stay in code). Launcher / Aqua /
/// Aqua Mist use [InoHomeIcons] SVGs instead.
abstract final class InoHomeIcons3d {
  static const scan = 'assets/icons/home/3d/qa_scan.png';
  static const documents = 'assets/icons/home/3d/qa_documents.png';
  static const reminder = 'assets/icons/home/3d/qa_reminder.png';
  static const voice = 'assets/icons/home/3d/qa_voice.png';

  static const identity = 'assets/icons/home/3d/vault_identity_glyph.png';
  static const property = 'assets/icons/home/3d/vault_property_glyph.png';
  static const investments = 'assets/icons/home/3d/vault_investments_glyph.png';
  static const cards = 'assets/icons/home/3d/vault_cards_glyph.png';

  static const attnExpiring = 'assets/icons/home/3d/attn_expiring.png';
  static const attnEmi = 'assets/icons/home/3d/attn_emi.png';
  static const attnPending = 'assets/icons/home/3d/attn_pending.png';
  static const attnInsurance = 'assets/icons/home/3d/attn_insurance.png';

  static const finArea = 'assets/icons/home/3d/fin_area.png';
  static const finEmi = 'assets/icons/home/3d/fin_emi.png';
  static const finSip = 'assets/icons/home/3d/fin_sip.png';
  static const finStamp = 'assets/icons/home/3d/fin_stamp.png';
  static const finUnit = 'assets/icons/home/3d/fin_unit.png';
  static const finTax = 'assets/icons/home/3d/fin_tax.png';

  /// Home My Vaults glyph for a built-in wallet name, or null.
  static String? vaultGlyph(String walletName) => switch (walletName) {
        'Identity Wallet' => identity,
        'Property Wallet' => property,
        'Investment Wallet' => investments,
        'Banking Wallet' => cards,
        _ => null,
      };

  /// Home finance-tool glyph for a tool id, or null.
  static String? financeGlyph(String toolId) => switch (toolId) {
        'area' => finArea,
        'emi' => finEmi,
        'sip' => finSip,
        'stamp' || 'valuation' => finStamp,
        'unit' => finUnit,
        'tax' || 'fx' || 'gold' => finTax,
        _ => null,
      };
}
