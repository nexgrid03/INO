import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/expense_models.dart';
import '../../services/expense_store.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../../utils/share_origin.dart';
import '../../widgets/dashboard/ino_card.dart';
import '../../widgets/expenses/expense_widgets.dart';
import '../../widgets/pressable_scale.dart';
import 'add_expense_screen.dart';

/// Read-only view of one transaction: all ITR fields, the attached receipt
/// (image / PDF) and a share action.
class TransactionDetailsScreen extends StatelessWidget {
  const TransactionDetailsScreen({super.key, required this.id});

  final String id;

  Future<void> _shareReceipt(BuildContext context, TransactionRecord t) async {
    if (t.receiptPath == null) return;
    final origin = shareOrigin(context);
    await Share.shareXFiles(
      [XFile(t.receiptPath!)],
      subject: t.description,
      text: 'Receipt for ${t.description}'
          '${t.reference != null ? ' (${t.reference})' : ''}',
      sharePositionOrigin: origin,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This record will be removed from your vault.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.critical))),
        ],
      ),
    );
    if (ok == true) {
      ExpenseStore.instance.remove(id);
      if (context.mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final t = store.byId(id);
            if (t == null) {
              return Center(
                child: Text('Transaction not found',
                    style: AppText.body.copyWith(color: palette.textSecondary)),
              );
            }
            final income = t.isIncome;
            return Column(
              children: [
                _Header(
                  onBack: () => Navigator.of(context).maybePop(),
                  onEdit: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AddExpenseScreen(existing: t))),
                  onDelete: () => _confirmDelete(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0,
                        AppSpacing.screen, AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Amount hero.
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.internal),
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryGreen
                                    .withValues(alpha: 0.28),
                                blurRadius: 22,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                _pill(t.type.label),
                                const SizedBox(width: 6),
                                _pill(t.category.label),
                              ]),
                              const SizedBox(height: AppSpacing.sm),
                              Text(t.description,
                                  style: AppText.subtitle.copyWith(
                                      color: Colors.white
                                          .withValues(alpha: 0.92))),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    '${income ? '+' : ''}${rupees(t.amount.round())}',
                                    style: AppText.bigNumber
                                        .copyWith(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Details.
                        InoCard(
                          radius: AppRadius.card,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.internal,
                              vertical: AppSpacing.xs),
                          child: Column(
                            children: [
                              _row(context, 'Category', t.category.label,
                                  t.category.icon,
                                  valueColor: t.category.color),
                              _divider(palette),
                              _row(context, 'Transaction ID',
                                  t.reference ?? '—', Icons.tag_rounded),
                              _divider(palette),
                              _row(context, 'Date & Time',
                                  formatTxnDateTime(t.dateTime),
                                  Icons.schedule_rounded),
                              if (t.vendorName != null) ...[
                                _divider(palette),
                                _row(context, 'Vendor', t.vendorName!,
                                    Icons.storefront_rounded),
                              ],
                              if (t.paymentMethod != null) ...[
                                _divider(palette),
                                _row(context, 'Payment Method',
                                    t.paymentMethod!.label,
                                    t.paymentMethod!.icon),
                              ],
                              if (t.gstAmount != null) ...[
                                _divider(palette),
                                _row(context, 'GST Amount',
                                    rupees(t.gstAmount!.round()),
                                    Icons.receipt_rounded),
                              ],
                              if (t.note != null && t.note!.trim().isNotEmpty) ...[
                                _divider(palette),
                                _row(context, 'Notes', t.note!.trim(),
                                    Icons.sticky_note_2_rounded),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Receipt.
                        Text('Receipt / Screenshot',
                            style: AppText.title
                                .copyWith(color: palette.textPrimary)),
                        const SizedBox(height: AppSpacing.sm),
                        if (!t.hasReceipt)
                          InoCard(
                            radius: AppRadius.card,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.image_not_supported_rounded,
                                      color: palette.textFaint, size: 36),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text('No receipt attached',
                                      style: AppText.body.copyWith(
                                          color: palette.textSecondary)),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          _ReceiptView(txn: t),
                          const SizedBox(height: AppSpacing.sm),
                          _ShareButton(onTap: () => _shareReceipt(context, t)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(text,
            style: AppText.label.copyWith(color: Colors.white, fontSize: 11)),
      );

  Widget _divider(AppPalette p) => Divider(height: 1, color: p.border);

  Widget _row(BuildContext context, String label, String value, IconData icon,
      {Color? valueColor}) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textFaint),
          const SizedBox(width: AppSpacing.sm),
          Text(label,
              style: AppText.body.copyWith(color: palette.textSecondary)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: AppText.subtitle.copyWith(
                    color: valueColor ?? palette.textPrimary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ReceiptView extends StatelessWidget {
  const _ReceiptView({required this.txn});

  final TransactionRecord txn;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (txn.receiptIsPdf) {
      return InoCard(
        radius: AppRadius.card,
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => OpenFilex.open(txn.receiptPath!),
        child: Row(
          children: [
            Container(
              width: AppSizes.iconContainer,
              height: AppSizes.iconContainer,
              decoration: BoxDecoration(
                color: AppColors.lightBlue.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded,
                  color: AppColors.lightBlue, size: 26),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('PDF receipt · tap to open',
                  style: AppText.body.copyWith(color: palette.textPrimary)),
            ),
            Icon(Icons.open_in_new_rounded, size: 18, color: palette.textFaint),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => _openFull(context, txn.receiptPath!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Image.file(
          File(txn.receiptPath!),
          width: double.infinity,
          height: 260,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text('Image unavailable',
                style: AppText.body.copyWith(color: palette.textSecondary)),
          ),
        ),
      ),
    );
  }

  void _openFull(BuildContext context, String path) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(child: Image.file(File(path))),
        ),
      ),
    ));
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: AppSizes.button,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.ios_share_rounded,
                    color: AppColors.darkGreen, size: 18),
                SizedBox(width: 8),
                Text('Download / Share',
                    style: TextStyle(
                        color: AppColors.darkGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget btn(IconData icon, VoidCallback onTap, [Color? color]) =>
        PressableScale(
          pressedScale: 0.9,
          child: Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              side: BorderSide(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: AppSizes.iconContainerSm,
                height: AppSizes.iconContainerSm,
                child: Icon(icon, size: 20, color: color ?? palette.textPrimary),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm,
          AppSpacing.screen, AppSpacing.md),
      child: Row(
        children: [
          btn(Icons.arrow_back_rounded, onBack),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Transaction',
                style: AppText.headline
                    .copyWith(color: palette.textPrimary, fontSize: 21)),
          ),
          btn(Icons.edit_rounded, onEdit, AppColors.primaryGreen),
          const SizedBox(width: AppSpacing.xs),
          btn(Icons.delete_outline_rounded, onDelete, AppColors.critical),
        ],
      ),
    );
  }
}
