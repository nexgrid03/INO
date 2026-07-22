import 'package:flutter/material.dart';

import '../../models/expense_models.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../utils/indian_number_format.dart';
import '../pressable_scale.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "21 Jul 2026".
String formatTxnDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "21 Jul 2026 · 2:30 PM".
String formatTxnDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${formatTxnDate(d)} · $h:${d.minute.toString().padLeft(2, '0')} $ap';
}

/// One transaction row: category icon, description, date/ID, amount.
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.txn, this.onTap});

  final TransactionRecord txn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final income = txn.isIncome;
    final accent = txn.category.color;
    final subtitle = txn.reference?.isNotEmpty == true
        ? '${formatTxnDate(txn.dateTime)} · ${txn.reference}'
        : (txn.vendorName?.isNotEmpty == true
            ? '${formatTxnDate(txn.dateTime)} · ${txn.vendorName}'
            : formatTxnDate(txn.dateTime));
    return PressableScale(
      pressedScale: 0.985,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm, horizontal: 4),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: AppSizes.iconContainerSm,
                      height: AppSizes.iconContainerSm,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Icon(txn.category.icon, color: accent, size: 21),
                    ),
                    if (txn.hasReceipt)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                              txn.receiptIsPdf
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.receipt_long_rounded,
                              size: 12,
                              color: AppColors.lightBlue),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(txn.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle.copyWith(
                              color: palette.textPrimary, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                              color: palette.textFaint, fontSize: 11.5)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${income ? '+' : ''}${rupees(txn.amount.round())}',
                  style: AppText.subtitle.copyWith(
                    color: income ? AppColors.primaryGreen : palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
