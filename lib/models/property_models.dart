import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'area_unit.dart';

/// Models backing the Property Wallet - a full digital property register.
///
/// Plain, UI-agnostic value objects with JSON round-tripping, persisted by
/// `PropertyStore`. Every money field is a plain `double` in the user's active
/// currency (formatted at the call site via `utils/indian_number_format.dart`),
/// so no currency conversion is ever implied.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum PropertyType { house, apartment, villa, plot, land, commercial, farmland, other }

extension PropertyTypeX on PropertyType {
  String get label => switch (this) {
        PropertyType.house => 'House',
        PropertyType.apartment => 'Apartment',
        PropertyType.villa => 'Villa',
        PropertyType.plot => 'Plot',
        PropertyType.land => 'Land',
        PropertyType.commercial => 'Commercial',
        PropertyType.farmland => 'Farmland',
        PropertyType.other => 'Other',
      };

  IconData get icon => switch (this) {
        PropertyType.house => Icons.home_rounded,
        PropertyType.apartment => Icons.apartment_rounded,
        PropertyType.villa => Icons.villa_rounded,
        PropertyType.plot => Icons.crop_landscape_rounded,
        PropertyType.land => Icons.landscape_rounded,
        PropertyType.commercial => Icons.storefront_rounded,
        PropertyType.farmland => Icons.agriculture_rounded,
        PropertyType.other => Icons.home_work_rounded,
      };

  static PropertyType fromName(String? name) => PropertyType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => PropertyType.house,
      );
}

enum PropertyStatus { owned, underConstruction, rented, leased, sold }

extension PropertyStatusX on PropertyStatus {
  String get label => switch (this) {
        PropertyStatus.owned => 'Owned',
        PropertyStatus.underConstruction => 'Under Construction',
        PropertyStatus.rented => 'Rented Out',
        PropertyStatus.leased => 'Leased',
        PropertyStatus.sold => 'Sold',
      };

  Color get color => switch (this) {
        // Brand accent — tracks Aqua teal / Classic sky like Document cards.
        PropertyStatus.owned => AppColors.primaryGreen,
        PropertyStatus.underConstruction => AppColors.warning,
        PropertyStatus.rented => const Color(0xFF4383EA),
        PropertyStatus.leased => const Color(0xFF9B6DE0),
        PropertyStatus.sold => const Color(0xFF64748B),
      };

  IconData get icon => switch (this) {
        PropertyStatus.owned => Icons.verified_rounded,
        PropertyStatus.underConstruction => Icons.construction_rounded,
        PropertyStatus.rented => Icons.key_rounded,
        PropertyStatus.leased => Icons.handshake_rounded,
        PropertyStatus.sold => Icons.sell_rounded,
      };

  static PropertyStatus fromName(String? name) =>
      PropertyStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => PropertyStatus.owned,
      );
}

/// The document slots a property can carry. [PropertyDocKind.custom] lets the
/// user label anything else.
enum PropertyDocKind {
  saleDeed,
  registration,
  taxReceipt,
  buildingPlan,
  insurance,
  ownershipCertificate,
  custom,
}

extension PropertyDocKindX on PropertyDocKind {
  String get label => switch (this) {
        PropertyDocKind.saleDeed => 'Sale Deed',
        PropertyDocKind.registration => 'Registration Document',
        PropertyDocKind.taxReceipt => 'Tax Receipt',
        PropertyDocKind.buildingPlan => 'Building Plan',
        PropertyDocKind.insurance => 'Property Insurance',
        PropertyDocKind.ownershipCertificate => 'Ownership Certificate',
        PropertyDocKind.custom => 'Other Document',
      };

  IconData get icon => switch (this) {
        PropertyDocKind.saleDeed => Icons.gavel_rounded,
        PropertyDocKind.registration => Icons.app_registration_rounded,
        PropertyDocKind.taxReceipt => Icons.receipt_long_rounded,
        PropertyDocKind.buildingPlan => Icons.architecture_rounded,
        PropertyDocKind.insurance => Icons.shield_rounded,
        PropertyDocKind.ownershipCertificate => Icons.workspace_premium_rounded,
        PropertyDocKind.custom => Icons.description_rounded,
      };

  static PropertyDocKind fromName(String? name) =>
      PropertyDocKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => PropertyDocKind.custom,
      );
}

// ---------------------------------------------------------------------------
// Attachments & co-owners
// ---------------------------------------------------------------------------

/// A file attached to a property. [path] is a local file path (picked from the
/// gallery / files); [linkedDocumentId] instead points at a document already in
/// the vault, so the two systems stay connected rather than duplicated.
class PropertyAttachment {
  const PropertyAttachment({
    required this.id,
    required this.kind,
    required this.name,
    this.path,
    this.linkedDocumentId,
    this.addedAt,
  });

  final String id;
  final PropertyDocKind kind;
  final String name;
  final String? path;
  final String? linkedDocumentId;
  final DateTime? addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        if (path != null) 'path': path,
        if (linkedDocumentId != null) 'documentId': linkedDocumentId,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
      };

  factory PropertyAttachment.fromJson(Map<String, dynamic> j) =>
      PropertyAttachment(
        id: j['id']?.toString() ?? '',
        kind: PropertyDocKindX.fromName(j['kind'] as String?),
        name: (j['name'] as String?) ?? '',
        path: j['path'] as String?,
        linkedDocumentId: j['documentId'] as String?,
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? ''),
      );
}

/// A co-owner and the share they hold.
class CoOwner {
  const CoOwner({required this.name, this.sharePercent, this.relationship});

  final String name;
  final double? sharePercent;
  final String? relationship;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (sharePercent != null) 'share': sharePercent,
        if (relationship != null) 'relationship': relationship,
      };

  factory CoOwner.fromJson(Map<String, dynamic> j) => CoOwner(
        name: (j['name'] as String?) ?? '',
        sharePercent: (j['share'] as num?)?.toDouble(),
        relationship: j['relationship'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Property
// ---------------------------------------------------------------------------

/// One property in the register. Only [id], [name] and [type] are required -
/// every other field is optional so a user can save a property immediately and
/// fill the legal / financial detail in later.
class Property {
  const Property({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.imagePath,
    this.purchaseDate,
    this.purchasePrice,
    this.currentValue,
    this.area,
    this.areaUnit = AreaUnit.squareFeet,
    // Location
    this.country,
    this.state,
    this.city,
    this.address,
    this.pinCode,
    this.mapsUrl,
    // Ownership
    this.ownerName,
    this.coOwners = const [],
    this.ownershipPercent,
    this.registrationNumber,
    this.registrationDate,
    // Legal
    this.willDetails,
    this.nomineeName,
    this.nomineeRelationship,
    this.legalHeirs = const [],
    this.taxId,
    this.encumbrance,
    this.hasLoan = false,
    this.loanProvider,
    this.outstandingLoan,
    // Financial
    this.emi,
    this.annualTax,
    this.maintenanceCharges,
    this.rentalIncome,
    this.otherExpenses,
    // Notes
    this.notes,
    this.reminderNote,
    this.attachments = const [],
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final PropertyType type;
  final PropertyStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? imagePath;
  final DateTime? purchaseDate;
  final double? purchasePrice;
  final double? currentValue;
  final double? area;
  final AreaUnit areaUnit;

  final String? country;
  final String? state;
  final String? city;
  final String? address;
  final String? pinCode;
  final String? mapsUrl;

  final String? ownerName;
  final List<CoOwner> coOwners;
  final double? ownershipPercent;
  final String? registrationNumber;
  final DateTime? registrationDate;

  final String? willDetails;
  final String? nomineeName;
  final String? nomineeRelationship;
  final List<String> legalHeirs;
  final String? taxId;
  final String? encumbrance;
  final bool hasLoan;
  final String? loanProvider;
  final double? outstandingLoan;

  final double? emi;
  final double? annualTax;
  final double? maintenanceCharges;
  final double? rentalIncome;
  final double? otherExpenses;

  final String? notes;
  final String? reminderNote;
  final List<PropertyAttachment> attachments;
  final bool isFavorite;

  /// Appreciation over the purchase price, as a fraction (0.18 = +18%). Null
  /// when either side is missing - never fabricated.
  double? get appreciation {
    final p = purchasePrice;
    final c = currentValue;
    if (p == null || c == null || p <= 0) return null;
    return (c - p) / p;
  }

  /// Gain/loss in currency, or null when it can't be derived.
  double? get gain {
    final p = purchasePrice;
    final c = currentValue;
    if (p == null || c == null) return null;
    return c - p;
  }

  /// Yearly running cost: tax + maintenance + other expenses.
  double get annualCost =>
      (annualTax ?? 0) + (maintenanceCharges ?? 0) + (otherExpenses ?? 0);

  /// A single-line location, skipping the parts that aren't filled in.
  String get locationLine {
    final parts = [city, state, country].where((p) => (p ?? '').isNotEmpty);
    return parts.join(', ');
  }

  /// The value used in portfolio totals: current estimate, else purchase price.
  double get portfolioValue => currentValue ?? purchasePrice ?? 0;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        type.label.toLowerCase().contains(q) ||
        status.label.toLowerCase().contains(q) ||
        (city ?? '').toLowerCase().contains(q) ||
        (state ?? '').toLowerCase().contains(q) ||
        (address ?? '').toLowerCase().contains(q) ||
        (ownerName ?? '').toLowerCase().contains(q) ||
        (registrationNumber ?? '').toLowerCase().contains(q);
  }

  Property copyWith({
    /// Only set when adopting the database's uuid after the record is first
    /// uploaded (see LocalCollectionStore.withId). Never change an id otherwise.
    String? id,
    String? name,
    PropertyType? type,
    PropertyStatus? status,
    DateTime? updatedAt,
    String? imagePath,
    bool clearImage = false,
    DateTime? purchaseDate,
    double? purchasePrice,
    double? currentValue,
    double? area,
    AreaUnit? areaUnit,
    String? country,
    String? state,
    String? city,
    String? address,
    String? pinCode,
    String? mapsUrl,
    String? ownerName,
    List<CoOwner>? coOwners,
    double? ownershipPercent,
    String? registrationNumber,
    DateTime? registrationDate,
    String? willDetails,
    String? nomineeName,
    String? nomineeRelationship,
    List<String>? legalHeirs,
    String? taxId,
    String? encumbrance,
    bool? hasLoan,
    String? loanProvider,
    double? outstandingLoan,
    double? emi,
    double? annualTax,
    double? maintenanceCharges,
    double? rentalIncome,
    double? otherExpenses,
    String? notes,
    String? reminderNote,
    List<PropertyAttachment>? attachments,
    bool? isFavorite,
  }) {
    return Property(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      currentValue: currentValue ?? this.currentValue,
      area: area ?? this.area,
      areaUnit: areaUnit ?? this.areaUnit,
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      address: address ?? this.address,
      pinCode: pinCode ?? this.pinCode,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      ownerName: ownerName ?? this.ownerName,
      coOwners: coOwners ?? this.coOwners,
      ownershipPercent: ownershipPercent ?? this.ownershipPercent,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      registrationDate: registrationDate ?? this.registrationDate,
      willDetails: willDetails ?? this.willDetails,
      nomineeName: nomineeName ?? this.nomineeName,
      nomineeRelationship: nomineeRelationship ?? this.nomineeRelationship,
      legalHeirs: legalHeirs ?? this.legalHeirs,
      taxId: taxId ?? this.taxId,
      encumbrance: encumbrance ?? this.encumbrance,
      hasLoan: hasLoan ?? this.hasLoan,
      loanProvider: loanProvider ?? this.loanProvider,
      outstandingLoan: outstandingLoan ?? this.outstandingLoan,
      emi: emi ?? this.emi,
      annualTax: annualTax ?? this.annualTax,
      maintenanceCharges: maintenanceCharges ?? this.maintenanceCharges,
      rentalIncome: rentalIncome ?? this.rentalIncome,
      otherExpenses: otherExpenses ?? this.otherExpenses,
      notes: notes ?? this.notes,
      reminderNote: reminderNote ?? this.reminderNote,
      attachments: attachments ?? this.attachments,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'imagePath': imagePath,
        'purchaseDate': purchaseDate?.toIso8601String(),
        'purchasePrice': purchasePrice,
        'currentValue': currentValue,
        'area': area,
        'areaUnit': areaUnit.name,
        'country': country,
        'state': state,
        'city': city,
        'address': address,
        'pinCode': pinCode,
        'mapsUrl': mapsUrl,
        'ownerName': ownerName,
        'coOwners': [for (final c in coOwners) c.toJson()],
        'ownershipPercent': ownershipPercent,
        'registrationNumber': registrationNumber,
        'registrationDate': registrationDate?.toIso8601String(),
        'willDetails': willDetails,
        'nomineeName': nomineeName,
        'nomineeRelationship': nomineeRelationship,
        'legalHeirs': legalHeirs,
        'taxId': taxId,
        'encumbrance': encumbrance,
        'hasLoan': hasLoan,
        'loanProvider': loanProvider,
        'outstandingLoan': outstandingLoan,
        'emi': emi,
        'annualTax': annualTax,
        'maintenanceCharges': maintenanceCharges,
        'rentalIncome': rentalIncome,
        'otherExpenses': otherExpenses,
        'notes': notes,
        'reminderNote': reminderNote,
        'attachments': [for (final a in attachments) a.toJson()],
        'isFavorite': isFavorite,
      };

  factory Property.fromJson(Map<String, dynamic> j) {
    double? num_(Object? v) => (v as num?)?.toDouble();
    DateTime? date(Object? v) => DateTime.tryParse(v as String? ?? '');
    return Property(
      id: j['id']?.toString() ?? '',
      name: (j['name'] as String?) ?? 'Property',
      type: PropertyTypeX.fromName(j['type'] as String?),
      status: PropertyStatusX.fromName(j['status'] as String?),
      createdAt: date(j['createdAt']) ?? DateTime.now(),
      updatedAt: date(j['updatedAt']) ?? DateTime.now(),
      imagePath: j['imagePath'] as String?,
      purchaseDate: date(j['purchaseDate']),
      purchasePrice: num_(j['purchasePrice']),
      currentValue: num_(j['currentValue']),
      area: num_(j['area']),
      areaUnit: AreaUnit.values.firstWhere(
        (u) => u.name == j['areaUnit'],
        orElse: () => AreaUnit.squareFeet,
      ),
      country: j['country'] as String?,
      state: j['state'] as String?,
      city: j['city'] as String?,
      address: j['address'] as String?,
      pinCode: j['pinCode'] as String?,
      mapsUrl: j['mapsUrl'] as String?,
      ownerName: j['ownerName'] as String?,
      coOwners: [
        for (final c in (j['coOwners'] as List?) ?? const [])
          CoOwner.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      ownershipPercent: num_(j['ownershipPercent']),
      registrationNumber: j['registrationNumber'] as String?,
      registrationDate: date(j['registrationDate']),
      willDetails: j['willDetails'] as String?,
      nomineeName: j['nomineeName'] as String?,
      nomineeRelationship: j['nomineeRelationship'] as String?,
      legalHeirs:
          (j['legalHeirs'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      taxId: j['taxId'] as String?,
      encumbrance: j['encumbrance'] as String?,
      hasLoan: (j['hasLoan'] as bool?) ?? false,
      loanProvider: j['loanProvider'] as String?,
      outstandingLoan: num_(j['outstandingLoan']),
      emi: num_(j['emi']),
      annualTax: num_(j['annualTax']),
      maintenanceCharges: num_(j['maintenanceCharges']),
      rentalIncome: num_(j['rentalIncome']),
      otherExpenses: num_(j['otherExpenses']),
      notes: j['notes'] as String?,
      reminderNote: j['reminderNote'] as String?,
      attachments: [
        for (final a in (j['attachments'] as List?) ?? const [])
          PropertyAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      isFavorite: (j['isFavorite'] as bool?) ?? false,
    );
  }
}
