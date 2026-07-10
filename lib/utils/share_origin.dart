import 'package:flutter/material.dart';

/// The popover anchor rect iPadOS needs when presenting the system share sheet.
///
/// `share_plus` **throws on iPad** if `sharePositionOrigin` is null, and ignores
/// the value entirely on iPhone and Android — so passing this at every share
/// call site is safe and changes nothing on non-iPad platforms.
///
/// Anchors to the given [context]'s render box; falls back to the screen centre
/// if the box isn't laid out yet.
Rect shareOrigin(BuildContext context) {
  final obj = context.findRenderObject();
  if (obj is RenderBox && obj.hasSize) {
    return obj.localToGlobal(Offset.zero) & obj.size;
  }
  final size = MediaQuery.of(context).size;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}
