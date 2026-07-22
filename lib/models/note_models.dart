import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The categories a note can be filed under. Order is intentional (shown in the
/// picker and filter row).
enum NoteCategory {
  personal,
  financial,
  tax,
  property,
  health,
  insurance,
  banking,
  investments,
  business,
  other,
}

extension NoteCategoryX on NoteCategory {
  String get label {
    switch (this) {
      case NoteCategory.personal:
        return 'Personal';
      case NoteCategory.financial:
        return 'Financial';
      case NoteCategory.tax:
        return 'Tax';
      case NoteCategory.property:
        return 'Property';
      case NoteCategory.health:
        return 'Health';
      case NoteCategory.insurance:
        return 'Insurance';
      case NoteCategory.banking:
        return 'Banking';
      case NoteCategory.investments:
        return 'Investments';
      case NoteCategory.business:
        return 'Business';
      case NoteCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case NoteCategory.personal:
        return Icons.person_rounded;
      case NoteCategory.financial:
        return Icons.account_balance_wallet_rounded;
      case NoteCategory.tax:
        return Icons.receipt_long_rounded;
      case NoteCategory.property:
        return Icons.home_work_rounded;
      case NoteCategory.health:
        return Icons.favorite_rounded;
      case NoteCategory.insurance:
        return Icons.shield_rounded;
      case NoteCategory.banking:
        return Icons.account_balance_rounded;
      case NoteCategory.investments:
        return Icons.trending_up_rounded;
      case NoteCategory.business:
        return Icons.business_center_rounded;
      case NoteCategory.other:
        return Icons.sticky_note_2_rounded;
    }
  }

  Color get color {
    switch (this) {
      case NoteCategory.personal:
        return const Color(0xFF0EA5A5);
      case NoteCategory.financial:
        return AppColors.primaryGreen;
      case NoteCategory.tax:
        return const Color(0xFF2563EB);
      case NoteCategory.property:
        return const Color(0xFFEA580C);
      case NoteCategory.health:
        return const Color(0xFFDC2626);
      case NoteCategory.insurance:
        return const Color(0xFF7C3AED);
      case NoteCategory.banking:
        return const Color(0xFF0891B2);
      case NoteCategory.investments:
        return const Color(0xFF16A34A);
      case NoteCategory.business:
        return const Color(0xFFB45309);
      case NoteCategory.other:
        return const Color(0xFF475569);
    }
  }

  static NoteCategory fromName(String? name) => NoteCategory.values.firstWhere(
        (c) => c.name == name,
        orElse: () => NoteCategory.other,
      );
}

/// A single note in the Notes Vault.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.isPinned = false,
    this.isArchived = false,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String description;
  final NoteCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final bool isPinned;
  final bool isArchived;
  final bool isFavorite;

  Note copyWith({
    String? title,
    String? description,
    NoteCategory? category,
    DateTime? updatedAt,
    List<String>? tags,
    bool? isPinned,
    bool? isArchived,
    bool? isFavorite,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  /// Case-insensitive match across title, description, category and tags.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        category.label.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'tags': tags,
        'isPinned': isPinned,
        'isArchived': isArchived,
        'isFavorite': isFavorite,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        category: NoteCategoryX.fromName(json['category'] as String?),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        isPinned: (json['isPinned'] as bool?) ?? false,
        isArchived: (json['isArchived'] as bool?) ?? false,
        isFavorite: (json['isFavorite'] as bool?) ?? false,
      );
}
