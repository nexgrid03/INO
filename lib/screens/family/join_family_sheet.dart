import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../data/family_vault_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/family_vault_models.dart';
import '../../services/family_vault_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/common/ino_loader.dart';

/// "Join a family": type the family's name, find it, and send the owner a
/// request to be let in.
///
/// Flow: name → `search_families` (exact, case-insensitive) →
///   * no match   → explains nothing was found under that name;
///   * one match  → shows it with a Send request button;
///   * several    → lists them (owner name + member count) to pick from.
/// Sending calls `request_to_join_family`, which notifies every owner/admin
/// of that family. Pops the created [VaultJoinRequest] on success.
Future<VaultJoinRequest?> showJoinFamilySheet(BuildContext context) {
  return showModalBottomSheet<VaultJoinRequest>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (_) => const _JoinFamilySheet(),
  );
}

class _JoinFamilySheet extends StatefulWidget {
  const _JoinFamilySheet();

  @override
  State<_JoinFamilySheet> createState() => _JoinFamilySheetState();
}

class _JoinFamilySheetState extends State<_JoinFamilySheet> {
  final _controller = TextEditingController();
  bool _searching = false;
  bool _searched = false;
  String? _sendingId;
  String? _error;
  List<FamilyMatch> _matches = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_searched || _error != null) {
        setState(() {
          _searched = false;
          _matches = const [];
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final l10n = AppLocalizations.of(context);
    final name = _controller.text.trim();
    if (name.length < 2) {
      setState(() => _error = l10n.t('familyNameRequired'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await FamilyVaultRepository.instance.searchFamilies(name);
      if (!mounted) return;
      setState(() {
        _matches = found;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeVaultError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _request(FamilyMatch match) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sendingId = match.id;
      _error = null;
    });
    try {
      final req = await FamilyVaultStore.instance.requestToJoin(match.id);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      Navigator.of(context).pop(req);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = l10n.t('couldNotSendJoinRequest'));
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final name = _controller.text.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.t('joinAFamily'),
                style: AppText.title.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.t('joinAFamilySubtitle'),
                style: AppText.caption.copyWith(color: palette.textSecondary)),
            const SizedBox(height: AppSpacing.md),

            Text(l10n.t('familyName'),
                style: AppText.label.copyWith(color: palette.textFaint)),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: AppText.body.copyWith(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.t('familyNameHint'),
                hintStyle: AppText.body.copyWith(color: palette.textFaint),
                prefixIcon:
                    Icon(Icons.family_restroom_rounded, color: palette.textFaint),
                filled: true,
                fillColor: palette.surfaceVariant,
                border: _border(palette.border),
                enabledBorder: _border(palette.border),
                focusedBorder: _border(AppColors.primaryGreen, 1.6),
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            if (!_searched)
              PressableScale(
                child: GestureDetector(
                  onTap: _searching ? null : _search,
                  child: Container(
                    height: AppSizes.button,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: AppShadows.glow(AppColors.primaryGreen),
                    ),
                    child: Center(
                      child: _searching
                          ? const InoLoader(size: 22, color: Colors.white)
                          : Text(l10n.t('findFamily'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                    ),
                  ),
                ),
              )
            else if (_matches.isEmpty)
              _Notice(
                icon: Icons.search_off_rounded,
                text: l10n.t('noFamilyNamed').replaceAll('{name}', name),
              )
            else ...[
              if (_matches.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(l10n.t('multipleFamiliesFound'),
                      style: AppText.caption
                          .copyWith(color: palette.textSecondary)),
                ),
              for (final m in _matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _MatchCard(
                    match: m,
                    sending: _sendingId == m.id,
                    onRequest: _sendingId == null ? () => _request(m) : null,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        borderSide: BorderSide(color: c, width: w),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: AppText.caption
                    .copyWith(color: palette.textPrimary, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.sending,
    required this.onRequest,
  });

  final FamilyMatch match;
  final bool sending;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final owner = match.ownerName?.trim();
    final meta = [
      if (owner != null && owner.isNotEmpty)
        l10n.t('ownedBy').replaceAll('{name}', owner),
      l10n.t('membersCountLabel').replaceAll('{count}', '${match.memberCount}'),
    ].join(' · ');

    final String? blocked = match.alreadyMember
        ? l10n.t('youAreAlreadyMember')
        : match.requestPending
            ? l10n.t('requestAlreadyPending')
            : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                decoration: BoxDecoration(
                  color: AppColors.tealMist,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(Icons.family_restroom_rounded,
                    color: AppColors.primaryGreen, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(match.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (blocked != null)
            Text(blocked,
                style: AppText.caption.copyWith(color: palette.textFaint))
          else
            PressableScale(
              child: GestureDetector(
                onTap: onRequest,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: sending
                      ? const InoLoader(size: 20, color: Colors.white)
                      : Text(l10n.t('sendJoinRequest'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
