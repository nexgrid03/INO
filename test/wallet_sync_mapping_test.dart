import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/area_unit.dart';
import 'package:inoapp/models/card_models.dart';
import 'package:inoapp/models/investment_models.dart';
import 'package:inoapp/models/property_models.dart';
import 'package:inoapp/services/card_store.dart';
import 'package:inoapp/services/investment_store.dart';
import 'package:inoapp/services/local_collection_store.dart';
import 'package:inoapp/services/property_store.dart';

/// Round-trips every wallet record through `toRow` → `fromRow`, the mapping
/// that moves it in and out of its Supabase wallet table.
///
/// Why this matters more than it looks: a wrong column name makes PostgREST
/// reject the whole insert, [LocalCollectionStore] swallows the error to keep
/// the record safe locally, and the user sees a property they saved that never
/// appears in the database - with nothing in the logs. That is exactly the bug
/// this suite exists to catch, and it cannot be caught by the analyzer.
///
/// The tests deliberately populate EVERY field. A field left at its default
/// would round-trip successfully even if the mapping dropped it entirely.
void main() {
  const uuid = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

  group('PropertyStore row mapping', () {
    final property = Property(
      id: 'prop_local_1',
      name: 'Lakeview Apartment',
      type: PropertyType.apartment,
      status: PropertyStatus.rented,
      createdAt: DateTime.utc(2026, 1, 5, 10, 30),
      updatedAt: DateTime.utc(2026, 7, 20, 8, 15),
      imagePath: '/data/img/flat.jpg',
      purchaseDate: DateTime.utc(2021, 3, 14),
      purchasePrice: 7250000.50,
      currentValue: 9100000,
      area: 1450.75,
      areaUnit: AreaUnit.squareFeet,
      country: 'India',
      state: 'Telangana',
      city: 'Hyderabad',
      address: '12-3-456, Banjara Hills',
      pinCode: '500034',
      mapsUrl: 'https://maps.example/xyz',
      ownerName: 'A. Sharma',
      coOwners: const [
        CoOwner(name: 'B. Sharma', sharePercent: 40, relationship: 'Spouse'),
      ],
      ownershipPercent: 60,
      registrationNumber: 'REG/2021/8891',
      registrationDate: DateTime.utc(2021, 3, 20),
      willDetails: 'Registered will, 2024',
      nomineeName: 'C. Sharma',
      nomineeRelationship: 'Daughter',
      legalHeirs: const ['B. Sharma', 'C. Sharma'],
      taxId: 'PTIN-99881',
      encumbrance: 'None',
      hasLoan: true,
      loanProvider: 'HDFC',
      outstandingLoan: 1850000,
      emi: 42500,
      annualTax: 12000,
      maintenanceCharges: 3600,
      rentalIncome: 28000,
      otherExpenses: 5000,
      notes: 'Tenant lease renews in March.',
      reminderNote: 'Renew lease',
      attachments: const [
        PropertyAttachment(
          id: 'att1',
          kind: PropertyDocKind.saleDeed,
          name: 'Sale deed',
          path: '/docs/deed.pdf',
        ),
      ],
      isFavorite: true,
    );

    test('survives a toRow → fromRow round trip with every field intact', () async {
      final store = PropertyStore.instance;
      final back = await store.fromRow({...await store.toRow(property), 'id': uuid});

      // The id comes from the database, not the local record.
      expect(back.id, uuid);

      expect(back.name, property.name);
      expect(back.type, property.type);
      expect(back.status, property.status);
      expect(back.imagePath, property.imagePath);
      expect(back.purchasePrice, property.purchasePrice);
      expect(back.currentValue, property.currentValue);
      expect(back.area, property.area);
      expect(back.areaUnit, property.areaUnit);

      expect(back.country, property.country);
      expect(back.state, property.state);
      expect(back.city, property.city);
      expect(back.address, property.address);
      expect(back.pinCode, property.pinCode);
      expect(back.mapsUrl, property.mapsUrl);

      expect(back.ownerName, property.ownerName);
      expect(back.ownershipPercent, property.ownershipPercent);
      expect(back.coOwners.single.name, 'B. Sharma');
      expect(back.coOwners.single.sharePercent, 40);
      expect(back.coOwners.single.relationship, 'Spouse');

      // The registration number lives in the shared `record_number` column.
      expect(back.registrationNumber, property.registrationNumber);

      expect(back.willDetails, property.willDetails);
      expect(back.nomineeName, property.nomineeName);
      expect(back.nomineeRelationship, property.nomineeRelationship);
      expect(back.legalHeirs, property.legalHeirs);
      expect(back.taxId, property.taxId);
      expect(back.encumbrance, property.encumbrance);
      expect(back.hasLoan, isTrue);
      expect(back.loanProvider, property.loanProvider);
      expect(back.outstandingLoan, property.outstandingLoan);

      expect(back.emi, property.emi);
      expect(back.annualTax, property.annualTax);
      expect(back.maintenanceCharges, property.maintenanceCharges);
      expect(back.rentalIncome, property.rentalIncome);
      expect(back.otherExpenses, property.otherExpenses);

      expect(back.notes, property.notes);
      expect(back.reminderNote, property.reminderNote);
      expect(back.attachments.single.name, 'Sale deed');
      expect(back.isFavorite, isTrue);
    });

    test('dates land as YYYY-MM-DD, which is what a `date` column accepts', () async {
      final row = await PropertyStore.instance.toRow(property);
      expect(row['purchase_date'], '2021-03-14');
      expect(row['registration_date'], '2021-03-20');
    });

    test('never sends id or auth_user_id - those belong to the database', () async {
      final row = await PropertyStore.instance.toRow(property);
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('auth_user_id'), isFalse);
    });

    test('reads numerics returned as strings by PostgREST', () async {
      // PostgREST serialises Postgres `numeric` as a JSON string to avoid
      // float precision loss. Parsing these as `num?` would null every price.
      final store = PropertyStore.instance;
      final back = await store.fromRow({
        ...await store.toRow(property),
        'id': uuid,
        'purchase_price': '7250000.50',
        'current_value': '9100000.00',
        'area': '1450.7500',
        'ownership_percent': '60.00',
      });
      expect(back.purchasePrice, 7250000.50);
      expect(back.currentValue, 9100000);
      expect(back.area, 1450.75);
      expect(back.ownershipPercent, 60);
    });
  });

  group('InvestmentStore row mapping', () {
    final investment = Investment(
      id: 'inv_local_1',
      name: 'Index Fund',
      type: InvestmentType.mutualFunds,
      createdAt: DateTime.utc(2025, 6, 1),
      updatedAt: DateTime.utc(2026, 7, 1),
      institution: 'Zerodha',
      accountNumber: '1234567890',
      units: 415.250000,
      purchasePrice: 182.4567,
      investedAmount: 75000,
      currentValue: 93250.25,
      purchaseDate: DateTime.utc(2025, 6, 2),
      maturityDate: DateTime.utc(2030, 6, 2),
      nominee: 'B. Sharma',
      notes: 'SIP, 5k monthly',
      attachments: const [],
      isFavorite: true,
    );

    test('survives a toRow → fromRow round trip', () async {
      final store = InvestmentStore.instance;
      final back = await store.fromRow({...await store.toRow(investment), 'id': uuid});

      expect(back.id, uuid);
      expect(back.name, investment.name);
      expect(back.type, investment.type);
      expect(back.institution, investment.institution);
      expect(back.accountNumber, investment.accountNumber);
      expect(back.units, investment.units);
      expect(back.purchasePrice, investment.purchasePrice);
      expect(back.investedAmount, investment.investedAmount);
      expect(back.currentValue, investment.currentValue);
      expect(back.nominee, investment.nominee);
      expect(back.notes, investment.notes);
      expect(back.isFavorite, isTrue);
    });

    test('dates land as YYYY-MM-DD', () async {
      final row = await InvestmentStore.instance.toRow(investment);
      expect(row['purchase_date'], '2025-06-02');
      expect(row['maturity_date'], '2030-06-02');
    });
  });

  group('CardStore row mapping', () {
    final card = SavedCard(
      id: 'card_local_1',
      name: 'Travel card',
      bank: 'HDFC',
      kind: CardKind.credit,
      network: CardNetwork.visa,
      holderName: 'A SHARMA',
      last4: '4321',
      expiryMonth: 11,
      expiryYear: 2029,
      themeKey: 'ocean',
      notes: 'Lounge access',
      isFavorite: true,
      createdAt: DateTime.utc(2026, 2, 2),
      updatedAt: DateTime.utc(2026, 7, 2),
    );

    test('survives a toRow → fromRow round trip', () async {
      final store = CardStore.instance;
      final back = await store.fromRow({...await store.toRow(card), 'id': uuid});

      expect(back.id, uuid);
      expect(back.name, card.name);
      expect(back.bank, card.bank);
      expect(back.kind, card.kind);
      expect(back.network, card.network);
      expect(back.holderName, card.holderName);
      expect(back.last4, card.last4);
      expect(back.expiryMonth, card.expiryMonth);
      expect(back.expiryYear, card.expiryYear);
      expect(back.themeKey, card.themeKey);
      expect(back.notes, card.notes);
      expect(back.isFavorite, isTrue);
    });

    test('sends only last4 - never a full card number', () async {
      final row = await CardStore.instance.toRow(card);
      // The table's check constraint is `^[0-9]{4}$`; anything longer would be
      // rejected by Postgres, so the mapping must never widen this field.
      expect(row['last4'], '4321');
      expect((row['last4'] as String).length, 4);
      for (final value in row.values.whereType<String>()) {
        expect(RegExp(r'^\d{12,19}$').hasMatch(value), isFalse,
            reason: 'a card-number-shaped value must never reach the table');
      }
    });
  });

  group('server id detection', () {
    test('recognises a uuid as a server id', () {
      expect(LocalCollectionStore.isServerId(uuid), isTrue);
      expect(
        LocalCollectionStore.isServerId('3F2504E0-4F89-11D3-9A0C-0305E82C3301'),
        isTrue,
      );
    });

    test('treats a locally-minted id as unsynced', () {
      // These are what `newId()` produces; they mark a record that exists only
      // on this device and must still be uploaded.
      expect(LocalCollectionStore.isServerId('prop_1753632000000000_0'), isFalse);
      expect(LocalCollectionStore.isServerId(''), isFalse);
      expect(LocalCollectionStore.isServerId('not-a-uuid'), isFalse);
    });
  });
}
