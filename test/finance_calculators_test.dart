import 'package:flutter_test/flutter_test.dart';
import 'package:inoapp/models/area_unit.dart';
import 'package:inoapp/models/currency.dart';
import 'package:inoapp/services/area_conversion_service.dart';
import 'package:inoapp/services/currency_rate_service.dart';
import 'package:inoapp/services/emi_calculator_service.dart';
import 'package:inoapp/services/gold_calculator_service.dart';
import 'package:inoapp/services/property_valuation_service.dart';
import 'package:inoapp/services/sip_calculator_service.dart';
import 'package:inoapp/utils/indian_number_format.dart';

void main() {
  group('Indian number format', () {
    test('groups the Indian way', () {
      expect(indianGroup(10920000), '1,09,20,000');
      expect(indianGroup(2500000), '25,00,000');
      expect(indianGroup(75000), '75,000');
      expect(indianGroup(5000), '5,000');
      expect(indianGroup(0), '0');
    });

    test('rupees + words', () {
      expect(rupees(10920000), '₹1,09,20,000');
      expect(rupees(5000), '₹5,000');
      expect(rupeesWords(10920000), '₹1.09 Cr');
      expect(rupeesWords(2500000), '₹25.00 L');
      expect(rupeesWords(-2500000), '-₹25.00 L');
    });
  });

  group('EMI calculator', () {
    const svc = EmiCalculatorService.instance;

    test('100000 @ 12% for 12 months', () {
      final r = svc.calculate(
        principal: 100000,
        annualRatePercent: 12,
        months: 12,
      );
      expect(r.emi, closeTo(8884.88, 0.5));
      expect(r.totalPayment, closeTo(r.emi * 12, 1e-6));
      expect(r.totalInterest, closeTo(r.totalPayment - 100000, 1e-6));
    });

    test('0% interest is principal / months', () {
      final r = svc.calculate(
        principal: 120000,
        annualRatePercent: 0,
        months: 12,
      );
      expect(r.emi, closeTo(10000, 1e-9));
      expect(r.totalInterest, closeTo(0, 1e-9));
    });

    test('invalid input returns zero', () {
      expect(
        svc.calculate(principal: 0, annualRatePercent: 10, months: 12).emi,
        0,
      );
    });
  });

  group('SIP calculator', () {
    const svc = SipCalculatorService.instance;

    test('10000/month @ 12% for 10 years', () {
      final r = svc.calculate(
        monthlyInvestment: 10000,
        annualReturnPercent: 12,
        years: 10,
      );
      expect(r.investedAmount, closeTo(1200000, 1e-6));
      expect(r.futureValue, closeTo(2323391, 50));
      expect(
        r.estimatedReturns,
        closeTo(r.futureValue - r.investedAmount, 1e-6),
      );
    });

    test('0% return is just the invested amount', () {
      final r = svc.calculate(
        monthlyInvestment: 5000,
        annualReturnPercent: 0,
        years: 2,
      );
      expect(r.futureValue, closeTo(120000, 1e-9));
      expect(r.estimatedReturns, closeTo(0, 1e-9));
    });
  });

  group('Gold calculator', () {
    const svc = GoldCalculatorService.instance;

    test('10g of 24K at 7000/g = 70000', () {
      final r = svc.calculate(
        weight: 10,
        unit: GoldWeightUnit.grams,
        purity: GoldPurity.k24,
        pricePerGram24k: 7000,
      );
      expect(r.pricePerGram, closeTo(7000, 1e-9));
      expect(r.totalValue, closeTo(70000, 1e-9));
    });

    test('22K scales by 22/24', () {
      final r = svc.calculate(
        weight: 10,
        unit: GoldWeightUnit.grams,
        purity: GoldPurity.k22,
        pricePerGram24k: 7000,
      );
      expect(r.pricePerGram, closeTo(7000 * 22 / 24, 1e-6));
      expect(r.totalValue, closeTo(10 * 7000 * 22 / 24, 1e-6));
    });

    test('1 tola = 11.6638 g', () {
      final r = svc.calculate(
        weight: 1,
        unit: GoldWeightUnit.tola,
        purity: GoldPurity.k24,
        pricePerGram24k: 7000,
      );
      expect(r.weightInGrams, closeTo(11.6638, 1e-9));
      expect(r.totalValue, closeTo(11.6638 * 7000, 1e-6));
    });
  });

  group('Property valuation', () {
    const svc = PropertyValuationService.instance;

    test('312 sq.yd @ 35000 = 1,09,20,000', () {
      final v = svc.marketValue(area: 312, ratePerUnit: 35000);
      expect(v, closeTo(10920000, 1e-6));
      expect(rupees(v), '₹1,09,20,000');
    });

    test('profit of 25L on a 50L → 75L holding', () {
      final p = svc.profitLoss(purchasePrice: 5000000, currentValue: 7500000);
      expect(p.amount, closeTo(2500000, 1e-6));
      expect(p.percent, closeTo(50, 1e-9));
      expect(p.isProfit, isTrue);
    });

    test('loss is negative and flagged', () {
      final p = svc.profitLoss(purchasePrice: 7500000, currentValue: 5000000);
      expect(p.amount, closeTo(-2500000, 1e-6));
      expect(p.isProfit, isFalse);
    });
  });

  group('Currency converter', () {
    final svc = CurrencyRateService.instance;
    final inr = Currencies.byCode('INR');
    final usd = Currencies.byCode('USD');
    final gbp = Currencies.byCode('GBP');

    // These tests describe the OFFLINE baseline, so no test may inherit live
    // rates fetched by another.
    setUp(svc.resetLiveRates);

    test('every currency in the registry has a rate', () {
      final missing = [
        for (final c in Currencies.all)
          if (!CurrencyRateService.ratesPerUsd.containsKey(c.code)) c.code,
      ];
      expect(
        missing,
        isEmpty,
        reason: 'currencies without a rate can never be converted',
      );
    });

    test('converts through USD in both directions', () {
      final perUsd = CurrencyRateService.ratesPerUsd;
      // 1 USD buys the table's INR rate.
      expect(svc.rate(usd, inr), closeTo(perUsd['INR']!, 1e-9));
      // ₹ → $ is the exact inverse.
      expect(svc.rate(inr, usd), closeTo(1 / perUsd['INR']!, 1e-12));
      // A cross pair (₹ → £) goes via USD.
      expect(
        svc.rate(inr, gbp),
        closeTo(perUsd['GBP']! / perUsd['INR']!, 1e-12),
      );
      // Converting to itself is identity, whatever the amount.
      expect(svc.convert(1234.5, inr, inr), closeTo(1234.5, 1e-9));
    });

    test('a typed rate overrides the table', () {
      expect(svc.convert(100, usd, inr, rateOverride: 90), closeTo(9000, 1e-9));
    });

    test('an unknown currency yields no rate instead of throwing', () {
      const fake = Currency(code: 'XXX', symbol: 'X', name: 'Test', flag: '🏳');
      expect(svc.rate(usd, fake), 0);
      expect(svc.convert(100, usd, fake), 0);
    });

    test('convertToAll covers every other currency, source excluded', () {
      final all = svc.convertToAll(1000, inr);
      expect(all.length, Currencies.all.length - 1);
      expect(all.any((c) => c.currency.code == 'INR'), isFalse);
      final usdRow = all.firstWhere((c) => c.currency.code == 'USD');
      expect(
        usdRow.value,
        closeTo(1000 / CurrencyRateService.ratesPerUsd['INR']!, 1e-9),
      );
      // Displays carry the target currency's symbol, never the source's.
      expect(usdRow.display.startsWith(r'$'), isTrue);
    });

    test('formats amounts by magnitude and rates with precision', () {
      // Small results keep cents; large ones read whole.
      expect(svc.format(11.5607, usd), r'$11.56');
      expect(svc.format(86500, inr), '₹86,500');
      expect(svc.formatRate(86.5), '86.5');
      final baselineInr = CurrencyRateService.ratesPerUsd['INR']!;
      expect(
        svc.rateLine(usd, inr),
        '1 USD = ${svc.formatRate(baselineInr)} INR',
      );
    });

    test('copy text lists the source amount then every currency', () {
      final text = svc.asCopyText(1000, inr);
      expect(text.startsWith('1000 INR ='), isTrue);
      expect(text, contains('USD '));
      expect(text, contains('GBP '));
    });

    test(
      'copy text can leave a currency out (the one shown as the result)',
      () {
        final text = svc.asCopyText(1000, inr, excludeCode: 'USD');
        expect(text, isNot(contains('\nUSD ')));
        expect(text, contains('GBP '));
      },
    );

    test('the rupee-pegged currencies hold their peg to a live INR rate', () {
      // The ECB feed carries INR but not NPR/BTN; the fixed pegs mean a live
      // rupee rate must move them too, or they drift away from the rupee.
      expect(svc.perUsd('NPR'), CurrencyRateService.ratesPerUsd['NPR']);
      svc.applyLiveRatesForTest(const {'INR': 100.0});
      expect(svc.perUsd('NPR'), closeTo(160, 1e-9)); // 1 INR = 1.60 NPR
      expect(svc.perUsd('BTN'), closeTo(100, 1e-9)); // at par with INR
      // A currency the feed does cover uses the feed value directly.
      expect(svc.perUsd('INR'), closeTo(100, 1e-9));
    });

    test('without a live fetch nothing claims to be live', () {
      expect(svc.isLive, isFalse);
      expect(svc.isLivePair(inr, usd), isFalse);
      expect(svc.fetchedAt, isNull);
      // The baseline still answers every pair.
      expect(svc.perUsd('INR'), CurrencyRateService.ratesPerUsd['INR']);
      expect(svc.perUsd('XXX'), isNull);
    });
  });

  group('Area units - grounds & bigha', () {
    const svc = AreaConversionService.instance;
    test('1 ground = 2400 sq.ft; 1 acre = 18.15 grounds', () {
      expect(
        svc.convert(1, AreaUnit.grounds, AreaUnit.squareFeet),
        closeTo(2400, 1e-9),
      );
      expect(
        svc.convert(1, AreaUnit.acres, AreaUnit.grounds),
        closeTo(18.15, 0.001),
      );
    });
    test('1 bigha = 14400 sq.ft (regional standard)', () {
      expect(
        svc.convert(1, AreaUnit.bigha, AreaUnit.squareFeet),
        closeTo(14400, 1e-9),
      );
    });
  });
}
