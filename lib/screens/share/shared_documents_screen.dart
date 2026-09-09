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
import '../../services/screen_security_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/pressable_scale.dart';
import '../auth/login_screen.dart';
import '../documents/add_document_screen.dart';
import '../../widgets/common/ino_loader.dart';

/// Palette for the recipient view, kept local so this screen matches the public
/// share page at `/s/{token}` rather than the app theme the owner happens to be
/// running. The slate/amber/rose tokens carry the status states; the aqua block
/// below carries the live share.
class _ShareWeb {
  static const green600 = Color(0xFF039855);
  static const blue50 = Color(0xFFF0F9FF);
  static const blue700 = Color(0xFF0369A1);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate700 = Color(0xFF334155);
  static const slate900 = Color(0xFF0F172A);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber800 = Color(0xFF92400E);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose600 = Color(0xFFE11D48);

  // ---- Aqua recipient theme ------------------------------------------------
  // The recipient view is the one screen a stranger sees, so it carries its own
  // calm palette: a mint page wash, one saturated teal hero, white cards.

  /// Page wash, top to bottom.
  static const pageTop = Color(0xFFD7EDEB);
  static const pageBottom = Color(0xFFEDF7F5);

  /// The hero band - deeper teal at the top-left, lighter toward the bottom.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E9490), Color(0xFF3EB9AE)],
  );

  static const teal = Color(0xFF0E9490);
  static const tealDeep = Color(0xFF0B7A77);
  static const tealSoft = Color(0xFFDCF0EE);
  static const tealLine = Color(0xFFBFE3DF);
  static const tealAction = Color(0xFF16A79F);
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
  String? _unlockToken;
  bool _unlockFailed = false;
  final _password = TextEditingController();
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    ScreenSecurityService.instance.enable();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    ScreenSecurityService.instance.disable();
    _ticker?.cancel();
    _ticker = null;
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final share = await ShareRepository.instance.fetchPublicShare(
      widget.token,
      unlockToken: _unlockToken,
    );
    if (!mounted) return;
    setState(() {
      _share = share;
      _loading = false;
    });
  }

  Future<void> _unlock() async {
    final raw = _password.text.trim();
    if (raw.isEmpty || _unlocking) return;
    setState(() => _unlocking = true);
    try {
      final token = await ShareRepository.instance.unlockPublicShare(widget.token, raw);
      if (token != null) {
        _unlockToken = token;
        _unlockFailed = false;
        await _load();
      } else {
        _unlockFailed = true;
        if (!mounted) return;
        _toast(AppLocalizations.of(context).t('sharePasswordIncorrect'),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
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
    return ShareRepository.instance.fetchSharedFile(
      widget.token,
      doc,
      download: download,
      unlockToken: _unlockToken,
    );
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
        text: l10n.t('sharedWithYouViaIno'),
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
      backgroundColor: _ShareWeb.pageBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_ShareWeb.pageTop, _ShareWeb.pageBottom],
          ),
        ),
        child: SafeArea(child: _body()),
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
      case PublicShareStatus.passwordRequired:
        return _PasswordGate(
          controller: _password,
          busy: _unlocking,
          wrong: _unlockFailed,
          onUnlock: _unlock,
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

class _PasswordGate extends StatelessWidget {
  const _PasswordGate({
    required this.controller,
    required this.busy,
    required this.wrong,
    required this.onUnlock,
    required this.onClose,
  });

  final TextEditingController controller;
  final bool busy;
  final bool wrong;
  final VoidCallback onUnlock;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Row(
          children: [
            const _InoLogoMark(),
            const Spacer(),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, color: _ShareWeb.slate500),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ShareWeb.slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('sharePasswordTitle'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ShareWeb.slate900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.t('sharePasswordHint'),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: _ShareWeb.slate500,
                ),
              ),
              if (wrong) ...[
                const SizedBox(height: 10),
                Text(
                  l10n.t('sharePasswordIncorrect'),
                  style: const TextStyle(
                    color: _ShareWeb.rose600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                enabled: !busy,
                onSubmitted: (_) => onUnlock(),
                decoration: InputDecoration(
                  hintText: l10n.t('password'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : onUnlock,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ShareWeb.green600,
                  ),
                  child: busy
                      ? const InoLoader(size: 20, color: Colors.white)
                      : Text(l10n.t('sharePasswordUnlock')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Active share (matches ActiveShare.tsx)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Active share
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
      children: [
        // Header: back, INO shield, "Secure share" badge.
        Row(
          children: [
            _RoundButton(
              icon: Icons.arrow_back_rounded,
              onTap: onClose,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
            const SizedBox(width: 12),
            const _InoLogoMark(),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _ShareWeb.tealLine),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 16, color: _ShareWeb.teal),
                  const SizedBox(width: 7),
                  Text(
                    l10n.t('secureShare'),
                    style: const TextStyle(
                      color: _ShareWeb.teal,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Hero + summary as ONE card, so the teal band and the details beneath
        // it read as a single object rather than two stacked panels.
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14004F4D),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                decoration:
                    const BoxDecoration(gradient: _ShareWeb.heroGradient),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('documentsSharedWithYou'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.t('sharedReviewHint'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _ShareWeb.tealSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.insert_drive_file_outlined,
                              size: 22, color: _ShareWeb.teal),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            count == 1
                                ? l10n.t('oneDocument')
                                : l10n
                                    .t('nDocuments')
                                    .replaceAll('{n}', '$count'),
                            style: const TextStyle(
                              color: _ShareWeb.slate900,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (expires != null && remaining != null) ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            l10n.t('expiresInLabel'),
                            style: const TextStyle(
                              color: _ShareWeb.slate700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: _CountdownPill(
                              remaining: remaining,
                              expiredLabel: l10n.t('expired'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _formatDateTime(expires),
                        style: const TextStyle(
                          color: _ShareWeb.slate500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Documents.
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 12),
          child: Text(
            l10n.t('sharedDocumentsCaption'),
            style: const TextStyle(
              color: _ShareWeb.slate500,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
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
              onDownload: share.viewOnly ? null : () => onDownload(docs[i]),
              onSave: share.viewOnly ? null : () => onSave(docs[i]),
            ),
            if (i < docs.length - 1) const SizedBox(height: 12),
          ],

        const SizedBox(height: 44),
        Text(
          l10n.t('shareFooterNote'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _ShareWeb.slate500,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// "10 Sept 2026, 12:43 pm" - the shape the public share page prints.
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
      'Sept',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour >= 12 ? 'pm' : 'am';
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $h:$m $ampm';
  }
}

/// A soft circular header control (back).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        pressedScale: 0.93,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _ShareWeb.tealLine),
            ),
            child: Icon(icon, size: 20, color: _ShareWeb.tealDeep),
          ),
        ),
      ),
    );
  }
}

/// The live "23h 59m 25s" pill.
///
/// Numbers carry the weight and the units sit back, so the figure that actually
/// moves is the one the eye lands on. Turns amber under an hour, rose once the
/// link has lapsed.
class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.remaining, required this.expiredLabel});

  final Duration remaining;
  final String expiredLabel;

  /// Coarse-to-fine number/unit pairs. Three segments is as much as the pill
  /// reads at a glance, so days push seconds off the end.
  List<List<String>> get _segments {
    final d = remaining;
    if (d.inDays > 0) {
      return [
        ['${d.inDays}', 'd'],
        ['${d.inHours % 24}', 'h'],
        ['${d.inMinutes % 60}', 'm'],
      ];
    }
    if (d.inHours > 0) {
      return [
        ['${d.inHours}', 'h'],
        ['${d.inMinutes % 60}', 'm'],
        ['${d.inSeconds % 60}', 's'],
      ];
    }
    if (d.inMinutes > 0) {
      return [
        ['${d.inMinutes}', 'm'],
        ['${d.inSeconds % 60}', 's'],
      ];
    }
    return [
      ['${math.max(0, d.inSeconds)}', 's'],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final expired = remaining.isNegative;
    final urgent = !expired && remaining.inHours < 1;

    final fg = expired
        ? _ShareWeb.rose600
        : urgent
            ? _ShareWeb.amber800
            : _ShareWeb.tealDeep;
    final bg = expired
        ? _ShareWeb.rose100
        : urgent
            ? _ShareWeb.amber100
            : _ShareWeb.tealSoft;

    final spans = <InlineSpan>[];
    for (final seg in _segments) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' '));
      spans.add(TextSpan(
        text: seg[0],
        style: TextStyle(
          color: fg,
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
      spans.add(TextSpan(
        text: seg[1],
        style: TextStyle(
          color: fg.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: fg),
          const SizedBox(width: 7),
          Flexible(
            child: expired
                ? Text(
                    expiredLabel,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : Text.rich(
                    TextSpan(children: spans),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    this.onDownload,
    this.onSave,
  });

  final SharedDoc doc;
  final bool busy;
  final VoidCallback onView;
  final VoidCallback? onDownload;
  final VoidCallback? onSave;

  String get _kind {
    final n = doc.name.toLowerCase();
    if (n.endsWith('.pdf') || doc.type.toLowerCase().contains('pdf')) {
      return 'PDF';
    }
    if (n.endsWith('.png')) return 'PNG';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'JPEG';
    if (n.endsWith('.webp')) return 'WEBP';
    final t = doc.type.trim();
    if (t.isEmpty || t.toLowerCase() == 'document') return 'FILE';
    return t.length <= 4 ? t.toUpperCase() : t.substring(0, 4).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F004F4D),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _ShareWeb.tealSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _kind,
                  style: const TextStyle(
                    color: _ShareWeb.tealDeep,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ShareWeb.slate900,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _kind,
                      style: const TextStyle(
                        color: _ShareWeb.slate500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: InoLoader(size: 24, color: _ShareWeb.teal),
                )
              else ...[
                _CircleAction(
                  icon: Icons.visibility_outlined,
                  tooltip: l10n.t('view'),
                  onTap: onView,
                ),
                if (onDownload != null) ...[
                  const SizedBox(width: 10),
                  _CircleAction(
                    icon: Icons.file_download_outlined,
                    tooltip: l10n.t('download'),
                    filled: true,
                    onTap: onDownload!,
                  ),
                ],
              ],
            ],
          ),
          // In-app recipients can also file the document into their own vault -
          // an affordance the public web page has no way to offer.
          if (onSave != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: _ShareWeb.slate200),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: busy ? null : onSave,
                style: TextButton.styleFrom(
                  foregroundColor: _ShareWeb.tealDeep,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                label: Text(
                  l10n.t('saveToInoVault'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A circular view / download control - outlined for the quiet action, filled
/// teal for the primary one.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        pressedScale: 0.93,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? _ShareWeb.tealAction : Colors.white,
              border: filled
                  ? null
                  : Border.all(color: _ShareWeb.tealLine, width: 1.4),
              boxShadow: filled
                  ? const [
                      BoxShadow(
                        color: Color(0x4016A79F),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 21,
              color: filled ? Colors.white : _ShareWeb.slate700,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _InoLogoMark(large: true),
          const SizedBox(height: 20),
          InoLoader(size: 28, color: _ShareWeb.green600),
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context).t('loadingSecureShare'),
            style: const TextStyle(
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 12),
                            child: Text(
                              l10n.t('tryAgain'),
                              style: const TextStyle(
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
            Text(
              l10n.t('securedByIno'),
              style: const TextStyle(
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

/// The INO shield - the mark the public share page leads with.
class _InoLogoMark extends StatelessWidget {
  const _InoLogoMark({this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final w = large ? 46.0 : 38.0;
    return SizedBox(
      width: w,
      height: w * 1.14,
      child: CustomPaint(
        painter: const _ShieldPainter(),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: w * 0.10),
            child: Text(
              'INO',
              style: TextStyle(
                color: Colors.white,
                fontSize: w * 0.30,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded shield silhouette behind [_InoLogoMark].
class _ShieldPainter extends CustomPainter {
  const _ShieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.18, 0)
      ..lineTo(w * 0.82, 0)
      ..quadraticBezierTo(w, 0, w, h * 0.16)
      ..lineTo(w, h * 0.52)
      ..quadraticBezierTo(w, h * 0.86, w / 2, h)
      ..quadraticBezierTo(0, h * 0.86, 0, h * 0.52)
      ..lineTo(0, h * 0.16)
      ..quadraticBezierTo(0, 0, w * 0.18, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17A9A2), Color(0xFF0B7A77)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter oldDelegate) => false;
}
