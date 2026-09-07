import 'package:flutter/material.dart';
import '../../models/country_code.dart';
import '../../theme/app_theme.dart';

/// Opens a bottom sheet to pick a country dial code with instant search.
Future<CountryCode?> showCountryCodePicker(
  BuildContext context, {
  CountryCode? initial,
}) {
  final effectiveInitial = initial ?? kCountryCodes.first;
  return showModalBottomSheet<CountryCode>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _CountryPickerSheet(initial: effectiveInitial),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.initial});

  final CountryCode initial;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _search = TextEditingController();
  List<CountryCode> _filtered = kCountryCodes;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = kCountryCodes;
      } else {
        _filtered = kCountryCodes.where((c) {
          return c.name.toLowerCase().contains(q) ||
              c.dialCode.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = palette.isDark;
    final bg = isDark ? palette.surface : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textFaint.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Select Country',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: palette.textSecondary,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search country or dial code',
                hintStyle: TextStyle(color: palette.textFaint, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: isDark ? palette.surfaceVariant : AppColors.tealPale.withValues(alpha: 0.2),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
              itemBuilder: (ctx, i) {
                final country = _filtered[i];
                final isSelected = country.dialCode == widget.initial.dialCode &&
                    country.name == widget.initial.name;
                return ListTile(
                  leading: Text(
                    country.flag,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    country.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.primaryGreen : palette.textPrimary,
                    ),
                  ),
                  trailing: Text(
                    country.dialCode,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.primaryGreen : palette.textSecondary,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(country),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
