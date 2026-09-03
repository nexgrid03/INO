import 'package:flutter/material.dart';

import '../../models/vault_item.dart';
import '../../state/vault_controller.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vault/vault_item_tile.dart';
import 'add_edit_vault_item_screen.dart';
import 'vault_item_detail_screen.dart';
import 'vault_unlock_screen.dart';

/// The Password Vault entry point. A single screen that renders the right state
/// (loading / setup / unlock / list / error) from [VaultController].
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _controller = VaultController.instance;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : AppColors.primaryGreen,
      ),
    );
  }

  Future<void> _openAdd() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddEditVaultItemScreen()),
    );
    if (created == true) _snack('Password saved securely.');
  }

  Future<void> _openDetail(VaultItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VaultItemDetailScreen(item: item)),
    );
  }

  Future<void> _confirmLock() async {
    await _controller.lock();
    _searchCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('Password Vault'),
        actions: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.status != VaultStatus.unlocked) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Lock vault',
                onPressed: _confirmLock,
                icon: const Icon(Icons.lock_outline_rounded),
              );
            },
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.status != VaultStatus.unlocked) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: _openAdd,
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          );
        },
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          switch (_controller.status) {
            case VaultStatus.loading:
              return Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2.6, color: AppColors.primaryGreen),
              );
            case VaultStatus.needsSetup:
              return const VaultLockView(isSetup: true);
            case VaultStatus.locked:
              return const VaultLockView(isSetup: false);
            case VaultStatus.error:
              return _ErrorView(
                message: _controller.error ?? 'Something went wrong.',
                onRetry: _controller.initialize,
              );
            case VaultStatus.unlocked:
              return _buildList(palette);
          }
        },
      ),
    );
  }

  Widget _buildList(AppPalette palette) {
    final items = _controller.items;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _controller.search,
            style: AppText.body.copyWith(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search passwords',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: palette.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _EmptyView(hasQuery: _controller.query.trim().isNotEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.xs, AppSpacing.md, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return VaultItemTile(
                      item: item,
                      onTap: () => _openDetail(item),
                      onToggleFavorite: () async {
                        try {
                          await _controller.toggleFavorite(item);
                        } catch (_) {
                          _snack('Could not update favorite.', error: true);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.hasQuery});
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.shield_outlined,
              size: 56,
              color: palette.textFaint,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasQuery ? 'No matches' : 'Your vault is empty',
              style: AppText.title.copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hasQuery
                  ? 'Try a different search term.'
                  : 'Tap Add to save your first password. Everything is '
                      'end-to-end encrypted.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 52, color: AppColors.critical),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
