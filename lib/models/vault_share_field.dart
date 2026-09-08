import 'package:flutter/material.dart';

/// One selectable line in the "choose what to share" checklist.
///
/// A Family Vault share is not all-or-nothing: a property carries a deed, an
/// address, a purchase price, a nominee and a loan balance, and the person
/// sharing it almost never wants the family to see all five. Each of those
/// becomes a [VaultShareField] the contributor can switch off before sending.
@immutable
class VaultShareField {
  const VaultShareField({
    required this.key,
    required this.label,
    this.preview,
    this.sensitive = false,
    this.isFile = false,
  });

  /// The JSON key in the source record, or [fileKey] for the attachment itself.
  final String key;

  /// Human label shown in the checklist ("Purchase Price", not "purchasePrice").
  final String label;

  /// A short rendering of the current value, so the contributor can see exactly
  /// what a member would read before agreeing to send it.
  final String? preview;

  /// Money, ID numbers and legal/nominee detail. Marked so the checklist can
  /// flag them — they stay ON by default, because silently withholding a field
  /// the user believes they shared is the worse failure.
  final bool sensitive;

  /// The uploaded file/photo rather than a data field.
  final bool isFile;

  /// The reserved key for "the document/photo attached to this record".
  static const String fileKey = '__file__';
}

/// Builds the checklist for a wallet record from its own JSON.
///
/// Deliberately data-driven rather than a hand-written list per wallet: the
/// property form alone has 30+ fields and grows, and a hard-coded checklist
/// (which is what the first version of the share sheet had — five fixed
/// switches named "price", "location", "registration_number", …) silently fails
/// to offer whatever was added last. Anything present in the record shows up.
class VaultShareFields {
  const VaultShareFields._();

  /// Keys that are plumbing, not information: identity, sync bookkeeping and
  /// the file pointers that [VaultShareField.fileKey] already represents.
  static const Set<String> _skip = {
    'id',
    'createdat',
    'updatedat',
    'isfavorite',
    'imagepath',
    'filepath',
    'attachments',
    'themekey',
    'consent',
    'authuserid',
    'documentid',
    'linkeddocumentid',
  };

  /// Substrings that make a field sensitive enough to call out in the UI.
  static const List<String> _sensitiveHints = [
    'price',
    'value',
    'amount',
    'invested',
    'loan',
    'emi',
    'tax',
    'income',
    'expense',
    'charge',
    'salary',
    'balance',
    'account',
    'number',
    'nominee',
    'heir',
    'will',
    'owner',
    'address',
    'pin',
    'last4',
    'holder',
  ];

  /// Labels that read better than a de-camel-cased key.
  static const Map<String, String> _labels = {
    'name': 'Name',
    'type': 'Type',
    'status': 'Status',
    'purchasedate': 'Purchase Date',
    'purchaseprice': 'Purchase Price',
    'currentvalue': 'Current Value',
    'area': 'Area',
    'areaunit': 'Area Unit',
    'country': 'Country',
    'state': 'State',
    'city': 'City',
    'address': 'Address',
    'pincode': 'PIN Code',
    'mapsurl': 'Map Location',
    'ownername': 'Owner Name',
    'coowners': 'Co-owners',
    'ownershippercent': 'Ownership Share',
    'registrationnumber': 'Registration Number',
    'registrationdate': 'Registration Date',
    'willdetails': 'Will Details',
    'nomineename': 'Nominee',
    'nomineerelationship': 'Nominee Relationship',
    'legalheirs': 'Legal Heirs',
    'taxid': 'Tax ID',
    'encumbrance': 'Encumbrance',
    'hasloan': 'Has Loan',
    'loanprovider': 'Loan Provider',
    'outstandingloan': 'Outstanding Loan',
    'emi': 'EMI',
    'annualtax': 'Annual Tax',
    'maintenancecharges': 'Maintenance Charges',
    'rentalincome': 'Rental Income',
    'otherexpenses': 'Other Expenses',
    'notes': 'Notes',
    'remindernote': 'Reminder Note',
    'reminderdate': 'Reminder Date',
    'institution': 'Institution',
    'accountnumber': 'Account / Folio Number',
    'units': 'Units',
    'investedamount': 'Invested Amount',
    'maturitydate': 'Maturity Date',
    'nominee': 'Nominee',
    'bank': 'Bank',
    'kind': 'Card Type',
    'network': 'Network',
    'holdername': 'Card Holder',
    'last4': 'Last 4 Digits',
    'expirymonth': 'Expiry Month',
    'expiryyear': 'Expiry Year',
    'category': 'Category',
    'recordnumber': 'Record Number',
    'issuedate': 'Issue Date',
    'expirydate': 'Expiry Date',
    'doctorname': 'Doctor',
    'tags': 'Tags',
  };

  /// The checklist for [json], newest-form-fields included automatically.
  ///
  /// [hasFile] adds the attachment line at the top — the one entry that is not
  /// a JSON key, because it decides whether the bytes travel at all.
  static List<VaultShareField> forRecord(
    Map<String, dynamic>? json, {
    required bool hasFile,
    String fileLabel = 'Attached document',
    String? filePreview,
  }) {
    final out = <VaultShareField>[];
    if (hasFile) {
      out.add(VaultShareField(
        key: VaultShareField.fileKey,
        label: fileLabel,
        preview: filePreview,
        isFile: true,
      ));
    }
    if (json == null) return out;

    for (final entry in json.entries) {
      final norm = entry.key.toLowerCase().replaceAll('_', '');
      if (_skip.contains(norm)) continue;
      final preview = describe(entry.value);
      // An empty field is not a disclosure decision — offering "Nominee: —" as
      // a switch just makes the list longer and the real choices harder to find.
      if (preview == null) continue;
      out.add(VaultShareField(
        key: entry.key,
        label: labelFor(entry.key),
        preview: preview,
        sensitive: _sensitiveHints.any(norm.contains),
      ));
    }
    return out;
  }

  /// The union of every field across [records], for sharing a whole wallet in
  /// one decision. Ordered by how many records actually carry the field, so the
  /// switches that affect the most items sit at the top.
  static List<VaultShareField> forWallet(
    List<Map<String, dynamic>?> records, {
    required bool anyHasFile,
  }) {
    final seen = <String, VaultShareField>{};
    final counts = <String, int>{};
    for (final r in records) {
      for (final f in forRecord(r, hasFile: false)) {
        counts[f.key] = (counts[f.key] ?? 0) + 1;
        // Keep the first preview only as an example of the field, and say so —
        // a wallet-wide switch does not have one value.
        seen.putIfAbsent(
          f.key,
          () => VaultShareField(
            key: f.key,
            label: f.label,
            preview: f.preview == null ? null : 'e.g. ${f.preview}',
            sensitive: f.sensitive,
          ),
        );
      }
    }
    final fields = seen.values.toList()
      ..sort((a, b) {
        final byCount = (counts[b.key] ?? 0).compareTo(counts[a.key] ?? 0);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });
    return [
      if (anyHasFile)
        const VaultShareField(
          key: VaultShareField.fileKey,
          label: 'Attached documents & photos',
          preview: 'Let the family open the files themselves',
          isFile: true,
        ),
      ...fields,
    ];
  }

  /// "purchasePrice" → "Purchase Price". Falls back to de-camel-casing so a
  /// field added to a model tomorrow still reads properly with no edit here.
  static String labelFor(String key) {
    final mapped = _labels[key.toLowerCase().replaceAll('_', '')];
    if (mapped != null) return mapped;
    final spaced = key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]}')
        .trim();
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// A one-line rendering of [value], or null when there is nothing to show.
  static String? describe(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is num) {
      if (value == 0) return null;
      return _trimNumber(value);
    }
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return null;
      // ISO timestamps are unreadable in a checklist; show the date part only.
      final asDate = DateTime.tryParse(t);
      if (asDate != null && t.length >= 10 && t.contains('-')) {
        return '${asDate.day.toString().padLeft(2, '0')}/'
            '${asDate.month.toString().padLeft(2, '0')}/${asDate.year}';
      }
      return t.length > 60 ? '${t.substring(0, 57)}…' : t;
    }
    if (value is List) {
      if (value.isEmpty) return null;
      final parts = <String>[];
      for (final v in value) {
        final d = v is Map ? describe(v['name'] ?? v.values.first) : describe(v);
        if (d != null) parts.add(d);
      }
      if (parts.isEmpty) return null;
      return parts.length > 3
          ? '${parts.take(3).join(', ')} +${parts.length - 3}'
          : parts.join(', ');
    }
    if (value is Map) {
      if (value.isEmpty) return null;
      return describe(value['name'] ?? value.values.first);
    }
    return value.toString();
  }

  static String _trimNumber(num v) {
    if (v is int || v == v.roundToDouble()) {
      final s = v.round().toString();
      // Indian grouping is what the rest of the app formats money with, but a
      // preview only needs to be readable, not localized — keep it plain.
      return s;
    }
    return v.toStringAsFixed(2);
  }

  /// Applies a checklist result to a record: the values the family may see.
  static Map<String, dynamic> applyMask(
    Map<String, dynamic>? json,
    Map<String, bool> mask,
  ) {
    if (json == null) return const {};
    final out = <String, dynamic>{};
    json.forEach((k, v) {
      final norm = k.toLowerCase().replaceAll('_', '');
      if (_skip.contains(norm)) return;
      // Absent from the mask means "not offered as a choice" (an empty field),
      // so it is not withheld data — it is no data.
      if (mask[k] == false) return;
      if (describe(v) == null) return;
      out[k] = v;
    });
    return out;
  }
}
