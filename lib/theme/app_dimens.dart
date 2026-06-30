import 'package:flutter/material.dart';

/// Design tokens for the INO app — the single source of truth for spacing,
/// radii, sizes, typography and semantic icons. Built on an 8dp grid so the
/// layout reads as one consistent system; widgets reference these instead of
/// hard-coding values.

/// Spacing scale (8dp grid + named layout gaps from the design spec).
class AppSpacing {
  AppSpacing._();

  // 8dp grid steps.
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  // Named layout gaps.
  static const double screen = 24; // screen edge padding
  static const double section = 28; // between sections
  static const double card = 16; // between cards
  static const double internal = 20; // inside a card
  static const double grid = 16; // grid spacing
}

/// Corner radii.
class AppRadius {
  AppRadius._();

  static const double card = 20;
  static const double large = 24; // hero / sheets
  static const double chip = 12;
  static const double pill = 999;
}

/// Fixed component sizes.
class AppSizes {
  AppSizes._();

  static const double iconContainer = 52;
  static const double iconContainerSm = 44;
  static const double button = 48;
  static const double avatar = 48;
}

/// Typography scale. Colour is applied at the call site (theme-aware) via
/// `.copyWith(color: …)`, keeping these reusable across light/dark.
class AppText {
  AppText._();

  static const TextStyle display = TextStyle(
      fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8);
  static const TextStyle bigNumber = TextStyle(
      fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.0);
  static const TextStyle headline = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5);
  static const TextStyle title = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2);
  static const TextStyle subtitle =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const TextStyle body =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const TextStyle caption =
      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500);
  static const TextStyle label =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
}

/// Semantic icon constants used across the home experience.
class AppIcons {
  AppIcons._();

  static const IconData scan = Icons.document_scanner_rounded;
  static const IconData addDocument = Icons.note_add_rounded;
  static const IconData wallet = Icons.account_balance_wallet_rounded;
  static const IconData reminder = Icons.alarm_add_rounded;
  static const IconData more = Icons.grid_view_rounded;
  static const IconData property = Icons.add_home_rounded;
  static const IconData insurance = Icons.add_moderator_rounded;
  static const IconData health = Icons.medical_services_rounded;
  static const IconData goal = Icons.flag_rounded;
  static const IconData upload = Icons.upload_file_rounded;
  static const IconData chevron = Icons.chevron_right_rounded;
}
