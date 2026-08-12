import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/public_share.dart';
import '../../repositories/share_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/pressable_scale.dart';
import '../auth/login_screen.dart';
import '../documents/add_document_screen.dart';

/// Brand tokens from [INO-Share-Web](https://github.com/nexgrid03/INO-Share-Web)
/// (`tailwind.config.ts` — ino.green + ino.blue). Kept local so the recipient
/// viewer matches the public Vercel page even when the app theme is Aqua Teal.
class _ShareWeb {
  static const green50 = Color(0xFFECFDF3);
  static const green600 = Color(0xFF039855);
  static const green700 = Color(0xFF027A48);
  static const green500 = Color(0xFF12B76A);
  static const blue50 = Color(0xFFF0F9FF);
  static const blue200 = Color(0xFFBAE6FD);
  static const blue500 = Color(0xFF0EA5E9);
  static const blue700 = Color(0xFF0369A1);
  static const slate50 = Color(0xFFF8FAFC);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber800 = Color(0xFF92400E);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose600 = Color(0xFFE11D48);

  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [green600, blue500],
  );
}

/// Recipient-facing viewer for a shared link/QR — styled to match the
/// INO-Share-Web `ActiveShare` page at `/s/{token}`.
///
/// Fetches public metadata from the `share` Edge Function (anonymous). Files
/// are streamed through the Edge Function so storage paths are never exposed.
class SharedDocumentsScreen extends StatefulWidget {
  const SharedDocumentsScreen({super.key, required this.token});

  final String token;

  @override
  State<SharedDocumentsScreen> createState() => _SharedDocumentsScreenState();
}

class _SharedDocumentsScreenState extends State<SharedDocumentsScreen> {
  PublicShare? _share;
  bool _loading = true;
  String? _busyDocId;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final share = await ShareRepository.instance.fetchPublicShare(widget.token);
    if (!mounted) return;
    setState(() {
      _share = share;
      _loading = false;
    });
  }

  PublicShareStatus get _status {
    final s = _share;
    if (s == null) return PublicShareStatus.error;
    if (s.status == PublicShareStatus.active &&
        s.expiresAt != null &&
        s.expiresAt!.isBefore(DateTime.now())) {
      return PublicShareStatus.expired;
    }
    return s.status;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.critical : _ShareWeb.green600,
      ),
    );
  }

  Future<SharedFile?> _fetchFile(SharedDoc doc, {required bool download}) {
    return ShareRepository.instance
        .fetchSharedFile(widget.token, doc, download: download);
  }

  Future<void> _view(SharedDoc doc) async {
    if (_busyDocId != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busyDocId = doc.id);
    try {
      final file = await _fetchFile(doc, download: false);
      if (file == null || !mounted) return;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      if (!mounted) return;
      final result = await OpenFilex.open(path, type: file.mimeType);
      if (result.type != ResultType.done) {
        _toast(l10n.t('noAppToOpenFile'), error: true);
      }
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(l10n.t('couldNotOpenDoc'), error: true);
    } finally {
      if (mounted) setState(() => _busyDocId = null);
    }
  }

  Future<void> _download(SharedDoc doc) async {
    if (_busyDocId != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busyDocId = doc.id);
    final origin = shareOrigin(context);
    try {
      final file = await _fetchFile(doc, download: true);
      if (file == null) throw StateError('empty');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path, mimeType: file.mimeType, name: file.filename)],
        subject: doc.name,
        text: 'Shared with you via INO',
        sharePositionOrigin: origin,
      );
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(l10n.t('couldNotDownloadDoc'), error: true);
    } finally {
      if (mounted) setState(() => _busyDocId = null);
    }
  }

  Future<void> _saveToVault(SharedDoc doc) async {
    if (_busyDocId != null) return;
    final l10n = AppLocalizations.of(context);

    if (AuthService.instance.currentUser == null) {
      _toast(l10n.t('signInToSaveVault'), error: true);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    setState(() => _busyDocId = doc.id);
    try {
      final file = await _fetchFile(doc, download: true);
      if (file == null) throw StateError('empty');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/ino_import_${file.filename}';
      await File(path).writeAsBytes(file.bytes, flush: true);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddDocumentScreen(
            initialWallet: 'Document Wallet',
            initialFilePath: path,
          ),
        ),
      );
    } on ShareException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(l10n.t('couldNotDownloadDoc'), error: true);
    } finally {
      if (mounted) setState(() => _busyDocId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ShareWeb.slate50,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _ShareWeb.slate50,
          gradient: RadialGradient(
            center: Alignment(-0.9, -1.0),
            radius: 1.2,
            colors: [
              Color(0x1412B76A), // green wash ~8%
              Colors.transparent,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Soft blue wash (top-right) matching Share-Web globals.css.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(1.0, -0.9),
                    radius: 1.1,
                    colors: [
                      Color(0x140EA5E9),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _LoadingState();
    switch (_status) {
      case PublicShareStatus.active:
        return _ActiveShareBody(
          share: _share!,
          busyDocId: _busyDocId,
          onView: _view,
          onDownload: _download,
          onSave: _saveToVault,
          onClose: () => Navigator.of(context).maybePop(),
        );
      case PublicShareStatus.expired:
        return _StatusCard(
          kind: _StatusKind.expired,
          onClose: () => Navigator.of(context).maybePop(),
        );
      case PublicShareStatus.revoked:
        return _StatusCard(
          kind: _StatusKind.revoked,
          onClose: () => Navigator.of(context).maybePop(),
        );
      case PublicShareStatus.notFound:
        return _StatusCard(
          kind: _StatusKind.notFound,
          onClose: () => Navigator.of(context).maybePop(),
        );
      case PublicShareStatus.error:
        return _StatusCard(
          kind: _StatusKind.error,
          detail: _share?.message,
          onRetry: _load,
          onClose: () => Navigator.of(context).maybePop(),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Active share (matches ActiveShare.tsx)
// ---------------------------------------------------------------------------

class _ActiveShareBody extends StatelessWidget {
  const _ActiveShareBody({
    required this.share,
    required this.busyDocId,
    required this.onView,
    required this.onDownload,
    required this.onSave,
    required this.onClose,
  });

  final PublicShare share;
  final String? busyDocId;
  final Future<void> Function(SharedDoc) onView;
  final Future<void> Function(SharedDoc) onDownload;
  final Future<void> Function(SharedDoc) onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final docs = share.documents;
    final count = share.count > 0 ? share.count : docs.length;
    final expires = share.expiresAt;
    final remaining = expires?.difference(DateTime.now());
    final urgent = remaining != null &&
        !remaining.isNegative &&
        remaining.inHours < 1;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // Header: logo + Secure share pill
        Row(
          children: [
            const _InoLogoMark(),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _ShareWeb.green50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded,
                      size: 14, color: _ShareWeb.green700),
                  const SizedBox(width: 6),
                  Text(
                    'Secure share',
                    style: TextStyle(
                      color: _ShareWeb.green700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, color: _ShareWeb.slate500),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Summary card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ShareWeb.slate200),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F101828),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x1A101828),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: const BoxDecoration(
                  gradient: _ShareWeb.brandGradient,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Documents shared with you',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Review, view and download the files below.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 20, color: _ShareWeb.green600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        count == 1
                            ? '1 document'
                            : '$count documents',
                        style: const TextStyle(
                          color: _ShareWeb.slate700,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (expires != null && remaining != null) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Expires in',
                                style: TextStyle(
                                  color: _ShareWeb.slate500,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _CountdownPill(
                                label: remaining.isNegative
                                    ? l10n.t('expired')
                                    : _shortCountdown(remaining),
                                urgent: urgent || remaining.isNegative,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(expires),
                            style: const TextStyle(
                              color: _ShareWeb.slate400,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Documents section
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'SHARED DOCUMENTS',
            style: TextStyle(
              color: _ShareWeb.slate400,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        if (docs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                l10n.t('noDocumentsYet'),
                style: const TextStyle(color: _ShareWeb.slate500),
              ),
            ),
          )
        else
          for (var i = 0; i < docs.length; i++) ...[
            _ShareDocRow(
              doc: docs[i],
              busy: busyDocId == docs[i].id,
              onView: () => onView(docs[i]),
              onDownload: () => onDownload(docs[i]),
              onSave: () => onSave(docs[i]),
            ),
            if (i < docs.length - 1) const SizedBox(height: 10),
          ],

        const SizedBox(height: 40),
        const Text(
          'These documents were shared securely via INO. Do not forward this '
          'link — it is private and time-limited.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ShareWeb.slate400,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  static String _shortCountdown(Duration d) {
    if (d.inDays > 0) {
      return '${d.inDays}d ${d.inHours % 24}h';
    }
    if (d.inHours > 0) {
      return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${math.max(0, d.inSeconds)}s';
  }

  static String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final m = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, ${local.year} · $h:$m $ampm';
  }
}

class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.label, required this.urgent});

  final String label;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: urgent ? _ShareWeb.amber100 : _ShareWeb.blue50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 14,
            color: urgent ? _ShareWeb.amber800 : _ShareWeb.blue700,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: urgent ? _ShareWeb.amber800 : _ShareWeb.blue700,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareDocRow extends StatelessWidget {
  const _ShareDocRow({
    required this.doc,
    required this.busy,
    required this.onView,
    required this.onDownload,
    required this.onSave,
  });

  final SharedDoc doc;
  final bool busy;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onSave;

  String get _kind {
    final n = doc.name.toLowerCase();
    if (n.endsWith('.pdf') || doc.type.toLowerCase().contains('pdf')) {
      return 'PDF';
    }
    if (n.endsWith('.png')) return 'PNG';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'JPG';
    if (n.endsWith('.webp')) return 'WEBP';
    final t = doc.type.trim();
    if (t.isEmpty || t.toLowerCase() == 'document') return 'FILE';
    return t.length <= 4 ? t.toUpperCase() : t.substring(0, 4).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ShareWeb.slate200),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_ShareWeb.green50, _ShareWeb.blue50],
                  ),
                ),
                child: Text(
                  _kind,
                  style: const TextStyle(
                    color: _ShareWeb.green700,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ShareWeb.slate800,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _kind,
                      style: const TextStyle(
                        color: _ShareWeb.slate500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: _ShareWeb.green600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  label: 'View',
                  icon: Icons.visibility_outlined,
                  filled: false,
                  onTap: busy ? null : onView,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionBtn(
                  label: 'Download',
                  icon: Icons.download_rounded,
                  filled: true,
                  onTap: busy ? null : onDownload,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: busy ? null : onSave,
            style: TextButton.styleFrom(
              foregroundColor: _ShareWeb.green700,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              l10n.t('saveToInoVault'),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      pressedScale: onTap == null ? 1 : 0.97,
      child: Material(
        color: filled ? _ShareWeb.green600 : _ShareWeb.blue50,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: filled
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _ShareWeb.blue200),
                  ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: filled ? Colors.white : _ShareWeb.blue700,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? Colors.white : _ShareWeb.blue700,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
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

// ---------------------------------------------------------------------------
// Loading / status (matches Loading.tsx + StatusScreen.tsx)
// ---------------------------------------------------------------------------

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InoLogoMark(large: true),
          SizedBox(height: 20),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: _ShareWeb.green600,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading secure share…',
            style: TextStyle(
              color: _ShareWeb.slate500,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatusKind { expired, revoked, notFound, error }

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.kind,
    required this.onClose,
    this.detail,
    this.onRetry,
  });

  final _StatusKind kind;
  final VoidCallback onClose;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (
      IconData icon,
      Color accent,
      Color ring,
      String title,
      String message,
    ) = switch (kind) {
      _StatusKind.expired => (
          Icons.timer_off_rounded,
          const Color(0xFFD97706),
          _ShareWeb.amber100,
          l10n.t('shareLinkExpiredTitle'),
          l10n.t('shareLinkExpiredBody'),
        ),
      _StatusKind.revoked => (
          Icons.block_rounded,
          _ShareWeb.rose600,
          _ShareWeb.rose100,
          l10n.t('shareLinkRevokedTitle'),
          l10n.t('shareLinkRevokedBody'),
        ),
      _StatusKind.notFound => (
          Icons.search_off_rounded,
          _ShareWeb.slate500,
          const Color(0xFFF1F5F9),
          l10n.t('linkNotFound'),
          l10n.t('linkNotFoundBody'),
        ),
      _StatusKind.error => (
          Icons.warning_amber_rounded,
          _ShareWeb.blue700,
          _ShareWeb.blue50,
          l10n.t('couldntLoadShare'),
          detail ?? l10n.t('checkConnection'),
        ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: _ShareWeb.slate500),
              ),
            ),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _ShareWeb.slate200),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F101828),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                  BoxShadow(
                    color: Color(0x1A101828),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const _InoLogoMark(large: true),
                  const SizedBox(height: 20),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                    child: Icon(icon, size: 30, color: accent),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _ShareWeb.slate900,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _ShareWeb.slate500,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 22),
                    PressableScale(
                      child: Material(
                        color: _ShareWeb.green600,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: onRetry,
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 22, vertical: 12),
                            child: Text(
                              'Try again',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Secured by INO',
              style: TextStyle(
                color: _ShareWeb.slate400,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// INO mark matching Share-Web `InoLogo.tsx` (green→blue rounded square).
class _InoLogoMark extends StatelessWidget {
  const _InoLogoMark({this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 40.0 : 32.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_ShareWeb.green500, _ShareWeb.blue500],
            ),
          ),
          child: Center(
            child: Container(
              width: size * 0.42,
              height: size * 0.42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Container(
                  width: size * 0.14,
                  height: size * 0.14,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'INO',
          style: TextStyle(
            color: _ShareWeb.slate900,
            fontSize: large ? 20 : 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}
