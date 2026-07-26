import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/card_models.dart';
import '../../services/card_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/ino_background.dart';
import '../../widgets/dashboard/fade_slide_in.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/wallet_modules/module_kit.dart';
import 'cards_wallet_screen.dart' show BankCardFace;

/// Add / edit a card.
///
/// The form is deliberately incomplete by design: it asks for the **last four
/// digits only** and has no CVV field at all, so what is saved can identify a
/// card but never be used to pay with one. A live preview at the top shows the
/// card face updating as the fields are filled.
class CardFormScreen extends StatefulWidget {
  const CardFormScreen({super.key, this.existing});

  final SavedCard? existing;

  @override
  State<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends State<CardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = CardStore.instance;

  final _name = TextEditingController();
  final _bank = TextEditingController();
  final _holder = TextEditingController();
  final _last4 = TextEditingController();
  final _notes = TextEditingController();

  CardKind _kind = CardKind.debit;
  CardNetwork _network = CardNetwork.visa;
  String _themeKey = kCardSkins.first.key;
  int? _expiryMonth;
  int? _expiryYear;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c == null) return;
    _name.text = c.name;
    _bank.text = c.bank;
    _holder.text = c.holderName;
    _last4.text = c.last4;
    _notes.text = c.notes ?? '';
    _kind = c.kind;
    _network = c.network;
    _themeKey = c.themeKey;
    _expiryMonth = c.expiryMonth;
    _expiryYear = c.expiryYear;
  }

  @override
  void dispose() {
    for (final c in [_name, _bank, _holder, _last4, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The card as currently typed - what the live preview renders and what
  /// [_save] persists.
  SavedCard get _draft => SavedCard(
        id: widget.existing?.id ?? 'preview',
        name: _name.text.trim().isEmpty ? 'New card' : _name.text.trim(),
        bank: _bank.text.trim(),
        kind: _kind,
        network: _network,
        holderName:
            _holder.text.trim().isEmpty ? 'Card holder' : _holder.text.trim(),
        last4: _last4.text.trim().padLeft(4, '•'),
        expiryMonth: _expiryMonth,
        expiryYear: _expiryYear,
        themeKey: _themeKey,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isFavorite: widget.existing?.isFavorite ?? false,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

  Future<void> _pickKind() async {
    final i = await showModulePicker(
      context,
      title: 'Card type',
      labels: [for (final k in CardKind.values) k.label],
      selectedIndex: CardKind.values.indexOf(_kind),
    );
    if (i == null || !mounted) return;
    setState(() => _kind = CardKind.values[i]);
  }

  Future<void> _pickNetwork() async {
    final i = await showModulePicker(
      context,
      title: 'Card network',
      labels: [for (final n in CardNetwork.values) n.label],
      selectedIndex: CardNetwork.values.indexOf(_network),
    );
    if (i == null || !mounted) return;
    setState(() => _network = CardNetwork.values[i]);
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final years = [for (var y = now.year; y <= now.year + 20; y++) y];
    final monthIndex = await showModulePicker(
      context,
      title: 'Expiry month',
      labels: [
        for (var m = 1; m <= 12; m++)
          '${m.toString().padLeft(2, '0')} · ${kMonthNames[m - 1]}',
      ],
      selectedIndex: _expiryMonth == null ? null : _expiryMonth! - 1,
    );
    if (monthIndex == null || !mounted) return;
    final yearIndex = await showModulePicker(
      context,
      title: 'Expiry year',
      labels: [for (final y in years) '$y'],
      selectedIndex: _expiryYear == null ? null : years.indexOf(_expiryYear!),
    );
    if (yearIndex == null || !mounted) return;
    setState(() {
      _expiryMonth = monthIndex + 1;
      _expiryYear = years[yearIndex];
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    FocusScope.of(context).unfocus();

    final now = DateTime.now();
    final card = SavedCard(
      id: widget.existing?.id ?? _store.newId('card'),
      name: _name.text.trim(),
      bank: _bank.text.trim(),
      kind: _kind,
      network: _network,
      holderName: _holder.text.trim(),
      last4: _last4.text.trim(),
      expiryMonth: _expiryMonth,
      expiryYear: _expiryYear,
      themeKey: _themeKey,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      isFavorite: widget.existing?.isFavorite ?? false,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    if (_isEdit) {
      await _store.update(card);
    } else {
      await _store.add(card);
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (_isEdit) await showSuccessBurst(context, 'Card updated');
    if (!mounted) return;
    Navigator.of(context).pop(card);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: InoBackground(
        showDots: false,
        child: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
              children: [
                ModuleHeader(
                  title: _isEdit ? 'Edit card' : 'Add card',
                  subtitle: 'Last 4 digits only · no CVV',
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Live preview ----
                FadeSlideIn(
                  child: BankCardFace(
                    card: _draft,
                    onTap: () {},
                    showFavorite: false,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Card details ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 50),
                  child: ModuleSection(
                    title: 'Card details',
                    icon: Icons.credit_card_rounded,
                    children: [
                      ModuleField(
                        label: 'Card name',
                        controller: _name,
                        hint: 'e.g. Travel card',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Name this card' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      ModuleField(
                        label: 'Bank name',
                        controller: _bank,
                        hint: 'e.g. HDFC Bank',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Enter the bank' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      ModuleField(
                        label: 'Card holder name',
                        controller: _holder,
                        hint: 'As printed on the card',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter the holder name'
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModulePickerField(
                              label: 'Card type',
                              value: _kind.label,
                              icon: Icons.style_rounded,
                              onTap: _pickKind,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModulePickerField(
                              label: 'Network',
                              value: _network.label,
                              icon: Icons.hub_rounded,
                              onTap: _pickNetwork,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ModuleField(
                              label: 'Last 4 digits',
                              controller: _last4,
                              hint: '1234',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                // Hard cap: four digits is all this app accepts.
                                LengthLimitingTextInputFormatter(4),
                              ],
                              validator: (v) => (v ?? '').trim().length == 4
                                  ? null
                                  : 'Enter the last 4 digits',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ModulePickerField(
                              label: 'Expiry',
                              value: _expiryMonth == null || _expiryYear == null
                                  ? null
                                  : '${_expiryMonth.toString().padLeft(2, '0')} / $_expiryYear',
                              hint: 'MM / YYYY',
                              icon: Icons.event_rounded,
                              trailingIcon: Icons.calendar_month_rounded,
                              onTap: _pickExpiry,
                            ),
                          ),
                        ],
                      ),
                      const _SecurityNote(),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Appearance ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: ModuleSection(
                    title: 'Card colour',
                    icon: Icons.palette_rounded,
                    accent: cardSkinFor(_themeKey).top,
                    subtitle: 'Make it look like the card in your wallet',
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final t in kCardSkins)
                            _ThemeSwatch(
                              theme: t,
                              selected: t.key == _themeKey,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _themeKey = t.key);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Notes ----
                FadeSlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: ModuleSection(
                    title: 'Notes',
                    icon: Icons.sticky_note_2_rounded,
                    accent: const Color(0xFF64748B),
                    children: [
                      ModuleField(
                        label: 'Notes',
                        controller: _notes,
                        hint: 'Limits, reward categories, billing date…',
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: GradientButton(
            label: _isEdit ? 'Save changes' : 'Add card',
            busy: _saving,
            onTap: _save,
          ),
        ),
      ),
    );
  }
}

/// The standing explanation of what this form deliberately does not ask for.
class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border:
            Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_rounded,
              size: 17, color: AppColors.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'INO never asks for your full card number or CVV. What is saved '
              'here identifies the card - it can never be used to pay.',
              style: AppText.caption.copyWith(
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final CardSkin theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PressableScale(
      pressedScale: 0.9,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 54,
          height: 38,
          decoration: BoxDecoration(
            gradient: theme.gradient,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.textPrimary : Colors.transparent,
              width: 2.2,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.bottom.withValues(alpha: 0.32),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}
