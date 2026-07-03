import 'package:flutter/material.dart';

import '../../data/wallet_repository.dart';
import '../../services/global_search_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/home/empty_state.dart';
import '../shell/shell_controller.dart';
import '../wallet/wallet_detail_screen.dart';

/// Global Search — live search across documents, reminders, categories and tags,
/// with recent searches, suggestions and a proper empty state.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _service = GlobalSearchService.instance;

  List<SearchHit> _results = const [];
  List<String> _recent = const [];
  String _query = '';
  bool _searching = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _service.invalidate();
    _loadRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final recent = await _service.recentSearches();
    if (mounted) setState(() => _recent = recent);
  }

  Future<void> _runSearch(String raw) async {
    final query = raw.trim();
    setState(() {
      _query = query;
      _searching = query.isNotEmpty;
    });
    if (query.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final id = ++_requestId;
    final hits = await _service.search(query);
    if (!mounted || id != _requestId) return; // a newer query superseded this
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  void _submit(String term) {
    _controller.text = term;
    _controller.selection =
        TextSelection.collapsed(offset: term.length);
    _service.addRecent(term);
    _runSearch(term);
    _loadRecent();
  }

  void _openHit(SearchHit hit) {
    _service.addRecent(_query);
    switch (hit.type) {
      case SearchHitType.reminder:
        Navigator.of(context).popUntil((r) => r.isFirst);
        ShellController.tab.value = 3; // Reminders tab
      case SearchHitType.document:
      case SearchHitType.category:
      case SearchHitType.tag:
        final category = hit.wallet == null
            ? null
            : SupabaseWalletRepository.categoryFor(hit.wallet!);
        if (category != null) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WalletDetailScreen(category: category)));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: _SearchField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _runSearch,
          onSubmitted: (v) => _submit(v),
          onClear: () {
            _controller.clear();
            _runSearch('');
          },
        ),
      ),
      body: SafeArea(top: false, child: _body(palette)),
    );
  }

  Widget _body(AppPalette palette) {
    if (_query.isEmpty) return _idleState(palette);
    if (_searching) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results for “$_query”',
        message: 'Try a document name, category, tag or reminder.',
        compact: true,
      );
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xl),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) =>
          _ResultTile(hit: _results[i], onTap: () => _openHit(_results[i])),
    );
  }

  Widget _idleState(AppPalette palette) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xl),
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            children: [
              Text('RECENT',
                  style: AppText.label.copyWith(color: palette.textFaint)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await _service.clearRecent();
                  _loadRecent();
                },
                child: Text('Clear',
                    style: AppText.caption.copyWith(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _recent)
                _Chip(
                    label: t,
                    icon: Icons.history_rounded,
                    onTap: () => _submit(t)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text('SUGGESTIONS',
            style: AppText.label.copyWith(color: palette.textFaint)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in GlobalSearchService.suggestions)
              _Chip(
                  label: s,
                  icon: Icons.trending_up_rounded,
                  onTap: () => _submit(s)),
          ],
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: palette.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Search documents, reminders, tags…',
        hintStyle: TextStyle(color: palette.textFaint, fontSize: 15),
        border: InputBorder.none,
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: palette.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hit.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(hit.icon, color: hit.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hit.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle
                            .copyWith(color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(hit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: palette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: palette.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: palette.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: AppText.caption.copyWith(color: palette.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
