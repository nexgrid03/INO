import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/perf/image_decode.dart';
import '../../services/wallet_media_sync.dart';

/// Renders a wallet record's photo whether it is still a device file or an
/// object in the `documents` bucket.
///
/// Every property thumbnail and hero used `Image.file(File(property.imagePath))`
/// directly, which is correct for exactly one case — the photo is on THIS phone.
/// After [WalletMediaSync] started uploading them, the stored value is an object
/// path, `File()` on it resolves to nothing, and every tile fell back to its
/// placeholder. This widget resolves the path first and paints the same file
/// either way.
///
/// The resolved file is cached on disk by [WalletMediaSync], so the download
/// happens once per object and later builds are as cheap as the old direct read.
class WalletMediaImage extends StatefulWidget {
  const WalletMediaImage({
    super.key,
    required this.path,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.zoomable = false,
    this.loading,
  });

  /// A device file path or a storage object path. Null renders [fallback].
  final String? path;

  /// Shown when there is no path, the file is gone, or the download failed.
  final Widget fallback;

  final BoxFit fit;

  /// Painted size. Applied to the fallback too, so a missing file leaves the
  /// layout exactly as a present one would — a placeholder that collapses to
  /// zero height makes the whole card jump when an image fails to load.
  final double? width;
  final double? height;

  /// Decode bounds. Property photos come off the camera at full resolution, so
  /// a 48px tile that decodes them whole evicts every other thumbnail from the
  /// image cache — pass the painted size here.
  final int? cacheWidth;
  final int? cacheHeight;

  /// Full-screen zoomable use. Decodes within the GPU's maximum texture size
  /// instead of at the file's own resolution — above that limit the image
  /// silently paints nothing at all, which reads as a document that failed to
  /// load. Ignored when [cacheWidth]/[cacheHeight] are given.
  final bool zoomable;

  /// Shown while a remote object is being fetched. Defaults to [fallback], so a
  /// list scrolls with its placeholders rather than flashing spinners.
  final Widget? loading;

  @override
  State<WalletMediaImage> createState() => _WalletMediaImageState();
}

class _WalletMediaImageState extends State<WalletMediaImage> {
  Future<File?>? _future;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(WalletMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _resolve();
  }

  void _resolve() {
    final path = widget.path?.trim();
    _future = (path == null || path.isEmpty)
        ? Future.value(null)
        : WalletMediaSync.instance.resolve(path);
  }

  /// Keeps a placeholder the same size as the image it stands in for.
  Widget _sized(Widget child) {
    if (widget.width == null && widget.height == null) return child;
    return SizedBox(width: widget.width, height: widget.height, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _sized(widget.loading ?? widget.fallback);
        }
        final file = snapshot.data;
        if (file == null) return _sized(widget.fallback);
        if (widget.zoomable &&
            widget.cacheWidth == null &&
            widget.cacheHeight == null) {
          return Image(
            image: zoomableFileImage(context, file),
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            errorBuilder: (_, _, _) => _sized(widget.fallback),
          );
        }
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          // A file that was deleted between resolve and paint must never break
          // the card it sits in.
          errorBuilder: (_, _, _) => _sized(widget.fallback),
        );
      },
    );
  }
}
