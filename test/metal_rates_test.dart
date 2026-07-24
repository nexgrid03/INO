import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inoapp/models/metal_rates.dart';
import 'package:inoapp/providers/metal_rates_provider.dart';
import 'package:inoapp/repositories/metals_repository.dart';
import 'package:inoapp/services/metals_api_service.dart';

// Sample upstream payloads (trimmed to the shape the parsers read).
String _spotBody(double bid, double ask) =>
    '[{"spreadProfilePrices":[{"bid":$bid,"ask":$ask}]}]';
const _fxBody = '{"amount":1.0,"base":"USD","rates":{"INR":83.0}}';

/// A fake API that returns a canned result or throws — for repo/provider tests.
class _FakeApi extends MetalsApiService {
  _FakeApi({this.result, this.error});

  final MetalRates? result;
  final MetalsException? error;
  int calls = 0;

  @override
  Future<MetalRates> fetchLatestRates() async {
    calls++;
    if (error != null) throw error!;
    return result!;
  }
}

MetalRates _sampleRates({DateTime? at}) => MetalRates.fromSpot(
  goldUsdPerOunce: 2000,
  silverUsdPerOunce: 24,
  usdToInr: 83,
  timestamp: at ?? DateTime.now().toUtc(),
  source: 'test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsing', () {
    test('parseSpotUsdPerOunce returns the mid price', () {
      expect(
        MetalsApiService.parseSpotUsdPerOunce(_spotBody(2000, 2002)),
        closeTo(2001, 1e-9),
      );
    });

    test('parseSpotUsdPerOunce returns null on malformed/empty bodies', () {
      expect(MetalsApiService.parseSpotUsdPerOunce('[]'), isNull);
      expect(MetalsApiService.parseSpotUsdPerOunce('not json'), isNull);
      expect(
        MetalsApiService.parseSpotUsdPerOunce('[{"spreadProfilePrices":[]}]'),
        isNull,
      );
    });

    test('parseUsdInr reads the INR rate', () {
      expect(MetalsApiService.parseUsdInr(_fxBody), closeTo(83.0, 1e-9));
    });

    test('parseUsdInr returns null when missing/invalid', () {
      expect(MetalsApiService.parseUsdInr('{"rates":{}}'), isNull);
      expect(MetalsApiService.parseUsdInr('{"rates":{"INR":0}}'), isNull);
      expect(MetalsApiService.parseUsdInr('garbage'), isNull);
    });
  });

  group('MetalRates model', () {
    test('fromSpot applies the troy-ounce → gram conversion', () {
      final r = _sampleRates();
      final expectedGold = 2000 * 83 / MetalRates.gramsPerTroyOunce;
      final expectedSilver = 24 * 83 / MetalRates.gramsPerTroyOunce;
      expect(r.goldPerGram, closeTo(expectedGold, 1e-6));
      expect(r.silverPerGram, closeTo(expectedSilver, 1e-6));
      expect(r.currency, 'INR');
    });

    test('22K gold is 22/24 of pure', () {
      final r = _sampleRates();
      expect(r.gold22kPerGram, closeTo(r.goldPerGram * 22 / 24, 1e-9));
    });

    test('encode/decode round-trips', () {
      final r = _sampleRates(at: DateTime.utc(2026, 7, 24, 11, 42));
      final back = MetalRates.decode(r.encode());
      expect(back, equals(r));
    });
  });

  group('MetalsApiService (mock client)', () {
    test('fetchLatestRates converts spot + FX into ₹/gram', () async {
      final client = MockClient((req) async {
        final u = req.url.toString();
        if (u.contains('/XAU/')) return http.Response(_spotBody(2000, 2002), 200);
        if (u.contains('/XAG/')) return http.Response(_spotBody(24, 24.2), 200);
        if (u.contains('frankfurter')) return http.Response(_fxBody, 200);
        return http.Response('not found', 404);
      });
      final svc = MetalsApiService(
        client: client,
        timeout: const Duration(seconds: 2),
        maxAttempts: 2,
      );

      final r = await svc.fetchLatestRates();
      expect(
        r.goldPerGram,
        closeTo(2001 * 83 / MetalRates.gramsPerTroyOunce, 1e-6),
      );
      expect(
        r.silverPerGram,
        closeTo(24.1 * 83 / MetalRates.gramsPerTroyOunce, 1e-6),
      );
      expect(r.currency, 'INR');
    });

    test('retries then throws a server error on repeated 500s', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response('boom', 500);
      });
      final svc = MetalsApiService(
        client: client,
        timeout: const Duration(seconds: 2),
        maxAttempts: 2,
      );

      await expectLater(
        svc.fetchLatestRates(),
        throwsA(
          isA<MetalsException>().having(
            (e) => e.type,
            'type',
            MetalsErrorType.server,
          ),
        ),
      );
      expect(calls, greaterThan(1), reason: 'should have retried');
    });
  });

  group('MetalsRepository caching', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('cache miss fetches; a fresh second read is a cache hit', () async {
      final api = _FakeApi(result: _sampleRates());
      final repo = MetalsRepository(api: api);

      final first = await repo.getRates();
      expect(first.fromCache, isFalse);
      expect(api.calls, 1);

      final second = await repo.getRates();
      expect(second.fromCache, isTrue);
      expect(api.calls, 1, reason: 'fresh cache must not hit the API again');
    });

    test('forceRefresh bypasses a fresh cache', () async {
      final api = _FakeApi(result: _sampleRates());
      final repo = MetalsRepository(api: api);

      await repo.getRates();
      await repo.getRates(forceRefresh: true);
      expect(api.calls, 2);
    });

    test('a stale cache triggers a refetch', () async {
      final stale = _sampleRates(
        at: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
      );
      SharedPreferences.setMockInitialValues({
        'metal_rates_cache_v1': stale.encode(),
      });
      final api = _FakeApi(result: _sampleRates());
      final repo = MetalsRepository(api: api);

      final result = await repo.getRates();
      expect(result.fromCache, isFalse);
      expect(api.calls, 1);
    });

    test('network failure with a cache falls back offline', () async {
      // Seed a cache via a good repo first.
      final good = MetalsRepository(api: _FakeApi(result: _sampleRates()));
      await good.getRates();

      final failing = MetalsRepository(
        api: _FakeApi(
          error: const MetalsException(MetalsErrorType.noInternet, 'x'),
        ),
      );
      final result = await failing.getRates(forceRefresh: true);
      expect(result.isOffline, isTrue);
      expect(result.fromCache, isTrue);
    });

    test('network failure with no cache rethrows', () async {
      final repo = MetalsRepository(
        api: _FakeApi(
          error: const MetalsException(MetalsErrorType.timeout, 'x'),
        ),
      );
      await expectLater(repo.getRates(), throwsA(isA<MetalsException>()));
    });
  });

  group('MetalRatesProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('ensureStarted loads data into a loaded state', () async {
      final provider = MetalRatesProvider(
        repository: MetalsRepository(api: _FakeApi(result: _sampleRates())),
      );
      await provider.ensureStarted();
      expect(provider.status, MetalRatesStatus.loaded);
      expect(provider.hasData, isTrue);
      expect(provider.isOffline, isFalse);
      provider.dispose();
    });

    test('error with no cached data surfaces an error state', () async {
      final provider = MetalRatesProvider(
        repository: MetalsRepository(
          api: _FakeApi(
            error: const MetalsException(MetalsErrorType.noInternet, 'x'),
          ),
        ),
      );
      await provider.ensureStarted();
      expect(provider.status, MetalRatesStatus.error);
      expect(provider.hasData, isFalse);
      expect(provider.error, isNotNull);
      provider.dispose();
    });
  });
}
