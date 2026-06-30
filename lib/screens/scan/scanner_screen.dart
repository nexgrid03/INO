import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/scan_models.dart';
import '../../widgets/scan/scan_controls.dart';
import '../../widgets/scan/scan_guidance_pill.dart';
import '../../widgets/scan/scanner_overlay.dart';

/// Screen 1 — the document scanner.
///
/// A full-bleed (simulated) camera viewport framed by the animated
/// [ScannerOverlay], live framing guidance, and the Gallery · Capture · Flash
/// controls. Stepping the guidance from "searching" to "ready" makes the
/// capture feel intelligent and trustworthy. The actual camera plugin slots
/// into [_SimulatedCameraFeed] without changing anything else.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.onClose,
    required this.onCapture,
    required this.onGallery,
  });

  final VoidCallback onClose;
  final VoidCallback onCapture;
  final VoidCallback onGallery;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  ScanGuidance _guidance = ScanGuidance.searching;
  bool _flashOn = false;
  final List<Timer> _timers = [];

  // The choreographed framing sequence — purely cosmetic, but it sells the
  // "live edge detection" feel.
  static const _sequence = <(int, ScanGuidance)>[
    (700, ScanGuidance.moveCloser),
    (1500, ScanGuidance.holdSteady),
    (2300, ScanGuidance.detected),
    (3000, ScanGuidance.ready),
  ];

  @override
  void initState() {
    super.initState();
    for (final step in _sequence) {
      _timers.add(Timer(Duration(milliseconds: step.$1), () {
        if (mounted) setState(() => _guidance = step.$2);
      }));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _capture() {
    HapticFeedback.mediumImpact();
    widget.onCapture();
  }

  @override
  Widget build(BuildContext context) {
    final detected = _guidance.isPositive;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    tooltip: 'Close',
                  ),
                  const Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Scan Document',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Position your document inside the frame',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48), // balances the close button
                ],
              ),
            ),
            // Camera viewport + overlay.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: const _SimulatedCameraFeed(),
                    ),
                    ScannerOverlay(detected: detected),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18,
                      child: Center(
                        child: ScanGuidancePill(guidance: _guidance),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Controls.
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
              child: ScanControls(
                onGallery: widget.onGallery,
                onCapture: _capture,
                onToggleFlash: () => setState(() => _flashOn = !_flashOn),
                flashOn: _flashOn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for the live camera preview. A real `CameraPreview` (from the
/// `camera` package) drops in here unchanged. Renders a dark feed with a faint
/// document silhouette so the frame reads correctly in the UI.
class _SimulatedCameraFeed extends StatelessWidget {
  const _SimulatedCameraFeed();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF1B2A30), Color(0xFF0A1316)],
        ),
      ),
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.66,
          child: Container(
            margin: const EdgeInsets.all(34),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined,
                    size: 44, color: Colors.white.withValues(alpha: 0.16)),
                const SizedBox(height: 10),
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    width: 120 - i * 22.0,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(3),
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
