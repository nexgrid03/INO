import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../property/area_converter_screen.dart';
import 'emi_calculator_screen.dart';
import 'gold_calculator_screen.dart';
import 'property_valuation_screen.dart';
import 'sip_calculator_screen.dart';

/// One entry in the Property & Finance Tools registry.
///
/// This registry is the single source of truth for the hub grid AND the Home
/// "Quick Tools" row — so adding a future calculator (GST, Stamp Duty, Rental
/// Yield, Retirement, FD …) is a one-line append here and it appears in both
/// places automatically. No screen needs editing.
class FinanceTool {
  const FinanceTool({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.builder,
  });

  final String id;
  final String title;

  /// A compact label for the Home quick-tools chips.
  final String shortTitle;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// Builds the tool's screen.
  final WidgetBuilder builder;
}

/// The available tools, in display order. Append new calculators here.
final List<FinanceTool> financeTools = [
  FinanceTool(
    id: 'area',
    title: 'Area Converter',
    shortTitle: 'Area',
    subtitle: 'Convert between all Indian land units',
    icon: Icons.straighten_rounded,
    color: AppColors.primaryGreen,
    builder: (_) => const AreaConverterScreen(),
  ),
  FinanceTool(
    id: 'valuation',
    title: 'Property Valuation',
    shortTitle: 'Valuation',
    subtitle: 'Area × rate → market value & profit',
    icon: Icons.home_work_rounded,
    color: AppColors.lightBlue,
    builder: (_) => const PropertyValuationScreen(),
  ),
  FinanceTool(
    id: 'emi',
    title: 'EMI Calculator',
    shortTitle: 'EMI',
    subtitle: 'Loan EMI, interest & total payment',
    icon: Icons.account_balance_rounded,
    color: AppColors.secondaryGreen,
    builder: (_) => const EmiCalculatorScreen(),
  ),
  FinanceTool(
    id: 'sip',
    title: 'SIP Calculator',
    shortTitle: 'SIP',
    subtitle: 'Project mutual-fund growth',
    icon: Icons.trending_up_rounded,
    color: const Color(0xFF8B6CEF),
    builder: (_) => const SipCalculatorScreen(),
  ),
  FinanceTool(
    id: 'gold',
    title: 'Gold Calculator',
    shortTitle: 'Gold',
    subtitle: 'Value gold by weight & purity',
    icon: Icons.diamond_rounded,
    color: AppColors.gold,
    builder: (_) => const GoldCalculatorScreen(),
  ),
];
