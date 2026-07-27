import '../models/area_unit.dart';
import '../models/property_models.dart';
import 'local_collection_store.dart';

/// The Property Wallet's register of properties, synced to `w_property_wallet`.
///
/// `shared_preferences` remains the offline cache; Supabase is the source of
/// truth, so a property survives a reinstall and appears on the user's other
/// devices. Records created before this store synced (or while offline) are
/// uploaded once on the next load - see [LocalCollectionStore].
class PropertyStore extends LocalCollectionStore<Property> {
  PropertyStore._();
  static final PropertyStore instance = PropertyStore._();

  @override
  String get storageKey => 'ino_properties';

  @override
  Map<String, dynamic> encode(Property item) => item.toJson();

  @override
  Property decode(Map<String, dynamic> json) => Property.fromJson(json);

  @override
  String idOf(Property item) => item.id;

  // ---- Supabase sync --------------------------------------------------------

  @override
  String get syncTable => 'w_property_wallet';

  @override
  Property withId(Property item, String id) => item.copyWith(id: id);

  /// Maps a [Property] onto its `w_property_wallet` columns.
  ///
  /// Two column names deliberately differ from the Dart field: `property_type`
  /// (because `type` collides with the shared base column set) and
  /// `record_number`, which the schema designates as the registration number.
  /// `name`/`status` reuse the base columns every wallet table has.
  @override
  Future<Map<String, dynamic>> toRow(Property p) async => {
        'name': p.name,
        'property_type': p.type.name,
        'status': p.status.name,
        'record_number': p.registrationNumber,
        'notes': p.notes,
        'is_favorite': p.isFavorite,
        'created_at': p.createdAt.toIso8601String(),
        'updated_at': p.updatedAt.toIso8601String(),
        // valuation
        'image_path': p.imagePath,
        'purchase_date': _date(p.purchaseDate),
        'purchase_price': p.purchasePrice,
        'current_value': p.currentValue,
        'area': p.area,
        'area_unit': p.areaUnit.name,
        // location
        'country': p.country,
        'state': p.state,
        'city': p.city,
        'address': p.address,
        'pin_code': p.pinCode,
        'maps_url': p.mapsUrl,
        // ownership
        'owner_name': p.ownerName,
        'co_owners': [for (final c in p.coOwners) c.toJson()],
        'ownership_percent': p.ownershipPercent,
        'registration_date': _date(p.registrationDate),
        // legal
        'will_details': p.willDetails,
        'nominee_name': p.nomineeName,
        'nominee_relationship': p.nomineeRelationship,
        'legal_heirs': p.legalHeirs,
        'tax_id': p.taxId,
        'encumbrance': p.encumbrance,
        'has_loan': p.hasLoan,
        'loan_provider': p.loanProvider,
        'outstanding_loan': p.outstandingLoan,
        // financial
        'emi': p.emi,
        'annual_tax': p.annualTax,
        'maintenance_charges': p.maintenanceCharges,
        'rental_income': p.rentalIncome,
        'other_expenses': p.otherExpenses,
        // misc
        'reminder_note': p.reminderNote,
        'attachments': [for (final a in p.attachments) a.toJson()],
      };

  @override
  Future<Property> fromRow(Map<String, dynamic> row) async => _fromRow(row);

  Property _fromRow(Map<String, dynamic> r) => Property(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Property',
        type: PropertyTypeX.fromName(r['property_type'] as String?),
        status: PropertyStatusX.fromName(r['status'] as String?),
        createdAt: _parseDate(r['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(r['updated_at']) ?? DateTime.now(),
        imagePath: r['image_path'] as String?,
        purchaseDate: _parseDate(r['purchase_date']),
        purchasePrice: _num(r['purchase_price']),
        currentValue: _num(r['current_value']),
        area: _num(r['area']),
        areaUnit: AreaUnit.values.firstWhere(
          (u) => u.name == r['area_unit'],
          orElse: () => AreaUnit.squareFeet,
        ),
        country: r['country'] as String?,
        state: r['state'] as String?,
        city: r['city'] as String?,
        address: r['address'] as String?,
        pinCode: r['pin_code'] as String?,
        mapsUrl: r['maps_url'] as String?,
        ownerName: r['owner_name'] as String?,
        coOwners: [
          for (final c in (r['co_owners'] as List?) ?? const [])
            CoOwner.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        ownershipPercent: _num(r['ownership_percent']),
        registrationNumber: r['record_number'] as String?,
        registrationDate: _parseDate(r['registration_date']),
        willDetails: r['will_details'] as String?,
        nomineeName: r['nominee_name'] as String?,
        nomineeRelationship: r['nominee_relationship'] as String?,
        legalHeirs: [
          for (final h in (r['legal_heirs'] as List?) ?? const []) h.toString(),
        ],
        taxId: r['tax_id'] as String?,
        encumbrance: r['encumbrance'] as String?,
        hasLoan: (r['has_loan'] as bool?) ?? false,
        loanProvider: r['loan_provider'] as String?,
        outstandingLoan: _num(r['outstanding_loan']),
        emi: _num(r['emi']),
        annualTax: _num(r['annual_tax']),
        maintenanceCharges: _num(r['maintenance_charges']),
        rentalIncome: _num(r['rental_income']),
        otherExpenses: _num(r['other_expenses']),
        notes: r['notes'] as String?,
        reminderNote: r['reminder_note'] as String?,
        attachments: [
          for (final a in (r['attachments'] as List?) ?? const [])
            PropertyAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        isFavorite: (r['is_favorite'] as bool?) ?? false,
      );

  /// `date` columns reject a full timestamp, so send YYYY-MM-DD only.
  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  /// Postgres `numeric` arrives as a String over PostgREST, not a num - parsing
  /// it as `num?` would silently null every price on the way back in.
  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Favourites first, then most recently updated.
  List<Property> get sorted {
    final list = [...items]..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return List.unmodifiable(list);
  }

  /// Total portfolio value across every property (current estimate, else the
  /// purchase price). Properties marked Sold are excluded - they're history.
  double get totalValue => items
      .where((p) => p.status != PropertyStatus.sold)
      .fold(0.0, (s, p) => s + p.portfolioValue);

  /// What was paid in total, for the same set of properties.
  double get totalInvested => items
      .where((p) => p.status != PropertyStatus.sold)
      .fold(0.0, (s, p) => s + (p.purchasePrice ?? 0));

  /// Portfolio-level appreciation, or null when no purchase price is recorded.
  double? get totalAppreciation {
    final invested = totalInvested;
    if (invested <= 0) return null;
    return (totalValue - invested) / invested;
  }

  /// Monthly rental income across rented / leased properties.
  double get monthlyRent =>
      items.fold(0.0, (s, p) => s + (p.rentalIncome ?? 0));

  /// Total outstanding loan across every property.
  double get totalLoan =>
      items.fold(0.0, (s, p) => s + (p.hasLoan ? (p.outstandingLoan ?? 0) : 0));

  int countOf(PropertyStatus status) =>
      items.where((p) => p.status == status).length;

  Future<void> toggleFavorite(String id) async {
    final p = byId(id);
    if (p == null) return;
    await update(p.copyWith(isFavorite: !p.isFavorite));
  }
}
