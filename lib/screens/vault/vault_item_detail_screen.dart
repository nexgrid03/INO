import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vault_item.dart';
import '../../state/vault_controller.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import 'add_edit_vault_item_screen.dart';

/// Read view for one credential: reveal/copy fields, edit, or delete.
class VaultItemDetailScreen extends StatefulWidget {
  const VaultItemDetailScreen({super.key, required this.item});

  final VaultItem item;

  @override
  State<VaultItemDetailScreen> createState() => _VaultItemDetailScreenState();
}

class _VaultItemDetailScreenState extends State<VaultItemDetailScreen> {
  late VaultItem _item = widget.item;
  bool _revealed = false;

  /// Copies [value] and schedules a clipboard wipe so secrets don't linger.
  Future<void> _copy(String label, String value, {bool sensitive = false}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sensitive ? '$label copied — clears in 30s' : '$label copied'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryGreen,
      ),
    );
    if (sensitive) {
      Future.delayed(const Duration(seconds: 30), () async {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      });
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditVaultItemScreen(existing: _item),
      ),
    );
    if (saved == true) {
      // Reflect the freshly-saved values from the controller.
      final updated = VaultController.instance.items
          .where((e) => e.id == _item.id)
          .cast<VaultItem?>()
          .firstWhere((e) => e != null, orElse: () => null);
      if (updated != null && mounted) {
        setState(() => _item = updated);
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete password?'),
        content: Text('“${_item.title}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.critical),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await VaultController.instance.deleteItem(_item.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete. Try again.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.critical,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('Details'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.iconContainer,
                height: AppSizes.iconContainer,
                decoration: BoxDecoration(
                  color: _item.category.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(_item.category.icon,
                    color: _item.category.color, size: 26),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_item.title,
                        style: AppText.headline
                            .copyWith(color: palette.textPrimary)),
                    Text(_item.category.label,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
              if (_item.favorite)
                const Icon(Icons.star_rounded, color: AppColors.warning),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_item.username.isNotEmpty)
            _field(
              palette,
              label: 'Username',
              value: _item.username,
              onCopy: () => _copy('Username', _item.username),
            ),
          _field(
            palette,
            label: 'Password',
            value: _revealed ? _item.password : '••••••••••••',
            onCopy: () => _copy('Password', _item.password, sensitive: true),
            trailing: IconButton(
              tooltip: _revealed ? 'Hide' : 'Reveal',
              onPressed: () => setState(() => _revealed = !_revealed),
              icon: Icon(_revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
            ),
          ),
          if ((_item.url ?? '').isNotEmpty)
            _field(
              palette,
              label: 'Website',
              value: _item.url!,
              onCopy: () => _copy('Website', _item.url!),
            ),
          if ((_item.notes ?? '').isNotEmpty)
            _field(
              palette,
              label: 'Notes',
              value: _item.notes!,
              onCopy: () => _copy('Notes', _item.notes!),
            ),
        ],
      ),
    );
  }

  Widget _field(
    AppPalette palette, {
    required String label,
    required String value,
    required VoidCallback onCopy,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppText.label
                        .copyWith(color: palette.textSecondary)),
                const SizedBox(height: 3),
                Text(value,
                    style: AppText.body.copyWith(color: palette.textPrimary)),
              ],
            ),
          ),
          ?trailing,
          IconButton(
            tooltip: 'Copy',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
