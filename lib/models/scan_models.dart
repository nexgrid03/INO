import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Models backing the Scan & OCR flow. UI-agnostic plain objects, hydrated today
/// by `ScanRepository`'s sample implementation and tomorrow by a real OCR
/// service — without touching the widgets.

// ---------------------------------------------------------------------------
// Detection confidence
// ---------------------------------------------------------------------------

enum DetectionConfidence { high, medium, low }

extension DetectionConfidenceX on DetectionConfidence {
  String get label {
    switch (this) {
      case DetectionConfidence.high:
        return 'High';
      case DetectionConfidence.medium:
        return 'Medium';
      case DetectionConfidence.low:
        return 'Low';
    }
  }

  /// Localized [label].
  String localizedLabel(AppLocalizations l10n) {
    switch (this) {
      case DetectionConfidence.high:
        return l10n.t('high');
      case DetectionConfidence.medium:
        return l10n.t('medium');
      case DetectionConfidence.low:
        return l10n.t('low');
    }
  }

  Color get color {
    switch (this) {
      case DetectionConfidence.high:
        return AppColors.primaryGreen;
      case DetectionConfidence.medium:
        return AppColors.warning;
      case DetectionConfidence.low:
        return AppColors.critical;
    }
  }
}

// ---------------------------------------------------------------------------
// Scanner state machine
// ---------------------------------------------------------------------------

/// The lifecycle of the live scanner, driven entirely by real camera/document
/// detection results (never pre-loaded):
///
///   idle             — camera live, no document found → instruction only
///   detecting        — a candidate is appearing (debounce before confirming)
///   documentDetected — a document is confirmed in-frame → green badge + glow
///   readyToScan      — document held stable at high confidence → ready badge
///   capturing        — shutter in progress
///   success          — capture succeeded (then returns to idle)
enum ScannerState {
  idle,
  detecting,
  documentDetected,
  readyToScan,
  capturing,
  success,
}

// ---------------------------------------------------------------------------
// Live framing guidance
// ---------------------------------------------------------------------------

/// Real-time hint shown over the camera as the user frames a document. The
/// scanner steps through these to feel responsive and trustworthy.
enum ScanGuidance { searching, moveCloser, holdSteady, detected, ready }

extension ScanGuidanceX on ScanGuidance {
  String get message {
    switch (this) {
      case ScanGuidance.searching:
        return 'Position your document inside the frame';
      case ScanGuidance.moveCloser:
        return 'Move closer';
      case ScanGuidance.holdSteady:
        return 'Hold steady';
      case ScanGuidance.detected:
        return 'Document detected';
      case ScanGuidance.ready:
        return 'Ready to scan';
    }
  }

  IconData get icon {
    switch (this) {
      case ScanGuidance.searching:
        return Icons.crop_free_rounded;
      case ScanGuidance.moveCloser:
        return Icons.zoom_in_map_rounded;
      case ScanGuidance.holdSteady:
        return Icons.back_hand_rounded;
      case ScanGuidance.detected:
        return Icons.check_circle_rounded;
      case ScanGuidance.ready:
        return Icons.verified_rounded;
    }
  }

  /// Detected / ready are "good to go" states (green, capture encouraged).
  bool get isPositive =>
      this == ScanGuidance.detected || this == ScanGuidance.ready;
}

// ---------------------------------------------------------------------------
// OCR result
// ---------------------------------------------------------------------------

/// Everything extracted from a scanned document. All fields are editable on the
/// results screen before the user continues to save.
class OcrResult {
  const OcrResult({
    required this.documentName,
    required this.detectedType,
    required this.suggestedWallet,
    required this.category,
    required this.confidence,
    this.documentNumber,
    this.issueDate,
    this.expiryDate,
    this.tags = const [],
    this.notes = '',
    this.fullName,
    this.dob,
    this.gender,
    this.fatherName,
    this.extractedFields = const {},
  });

  final String documentName;
  final String? documentNumber;
  final DateTime? issueDate;
  final DateTime? expiryDate;

  /// Structured identity fields extracted from ID documents (Aadhaar / PAN / …).
  /// Null when not applicable or not detected. Shown as editable inputs on the
  /// review screen and folded into the saved document's notes.
  final String? fullName;
  final String? dob; // kept as the raw detected string, e.g. "01-01-1998"
  final String? gender;
  final String? fatherName;

  /// Auto-detection: what kind of document this looks like ("PAN Card").
  final String detectedType;

  /// Auto-detection: which wallet it should be filed under ("Identity Wallet").
  final String suggestedWallet;

  /// Detected category ("Identity").
  final String category;
  final DetectionConfidence confidence;
  final List<String> tags;
  final String notes;

  /// All OCR-extracted fields keyed by semantic key (name, number, dob, gender,
  /// fatherName, and type-specific extras like expiryDate / nationality /
  /// validity / vehicleClass). Persisted with the document so every extracted
  /// field is visible again on reopen — not just the core four.
  final Map<String, String> extractedFields;

  OcrResult copyWith({
    String? documentName,
    String? documentNumber,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? detectedType,
    String? suggestedWallet,
    String? category,
    DetectionConfidence? confidence,
    List<String>? tags,
    String? notes,
    String? fullName,
    String? dob,
    String? gender,
    String? fatherName,
    Map<String, String>? extractedFields,
  }) {
    return OcrResult(
      documentName: documentName ?? this.documentName,
      documentNumber: documentNumber ?? this.documentNumber,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      detectedType: detectedType ?? this.detectedType,
      suggestedWallet: suggestedWallet ?? this.suggestedWallet,
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      fullName: fullName ?? this.fullName,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      fatherName: fatherName ?? this.fatherName,
      extractedFields: extractedFields ?? this.extractedFields,
    );
  }
}
