// C23 food_search_controller_test (FOOD-14 client half, FOOD-22 wiring):
// explicit submit, 3-character minimum, 600 ms debounce, last-results cache,
// offline bundled results and the closed failure phases. The clock is the
// widget-test fake clock, so the 599/600 ms boundary is exact.
import 'dart:async';

import 'package:fitness_app/features/food_diary/data/generic_foods.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:flutter_test/flutter_test.dart';

String _row(int fdc, String name) =>
    '{"id":"gen:$fdc","name":"$name","category":"T","fdcId":$fdc,'
    '"per100g":{"kcal":100,"proteinG":5,"carbsG":10,"fatG":4}}';

final GenericFoodTable _table = GenericFoodTable.parse(
    '{"version":1,"foods":[${_row(1, 'Rice, white')},${_row(2, 'Rice, brown')},'
    '${_row(3, 'Chicken breast')}]}');

const _cand = FoodCandidate(
  foodRef: 'off:111',
  name: 'Rice pudding',
  per100g: Per100g(kcal: 120, proteinG: 3, carbsG: 20, fatG: 3),
  source: FoodSource.off,
);

FoodSearchController _ctrl(FoodApi api,
        {bool server = true, GenericFoodTable? table, String lang = 'en'}) =>
    FoodSearchController(
      api: api,
      table: table ?? _table,
      serverEnabled: server,
      languageCode: lang,
    );

/// A search that completes only when the test says so.
class _HeldApi extends FakeFoodApi {
  final List<Completer<SearchResults>> pending = [];

  @override
  Future<SearchResults> searchFoods(
    String query, {
    required String languageCode,
    FoodSearchScope scope = FoodSearchScope.both,
    int limit = 20,
  }) {
    searchCalls++;
    lastQuery = query;
    final c = Completer<SearchResults>();
    pending.add(c);
    return c.future;
  }
}

class _ThrowingApi extends FakeFoodApi {
  @override
  Future<SearchResults> searchFoods(
    String query, {
    required String languageCode,
    FoodSearchScope scope = FoodSearchScope.both,
    int limit = 20,
  }) async =>
      throw StateError('parse');
}

void main() {
  group('table load and failure (FL-F1)', () {
    test('a table that loads later keeps the query and the server results',
        () async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api, table: GenericFoodTable.empty());
      c.submit('rice');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(c.state.remote, isNotEmpty);
      expect(c.state.local, isEmpty);
      c.setTable(_table);
      expect(c.state.query, 'rice');
      expect(c.state.remote, isNotEmpty, reason: 'server results survive');
      expect(c.state.local, isNotEmpty, reason: 'local hits are recomputed');
      expect(api.searchCalls, 1, reason: 'the cache is intact, no refetch');
      c.dispose();
    });

    test('a failed table is an error, never "nothing found"', () {
      final c = _ctrl(FakeFoodApi(), server: false, table: GenericFoodTable.empty());
      c.setTableFailed();
      c.onChanged('rice');
      expect(c.state.phase, SearchPhase.error);
      c.setTable(_table);
      c.onChanged('rice');
      expect(c.state.phase, SearchPhase.results);
      c.dispose();
    });
  });

  group('unexpected errors (FL-F2)', () {
    test('a non-FoodApi error ends in the error phase, not a stuck loading',
        () async {
      final c = _ctrl(_ThrowingApi(), table: GenericFoodTable.empty());
      c.submit('rice');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(c.state.phase, SearchPhase.error);
      c.dispose();
    });
  });

  group('typing (no network)', () {
    testWidgets('empty input is idle; 1 and 2 characters are tooShort',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.onChanged('');
      expect(c.state.phase, SearchPhase.idle);
      c.onChanged('r');
      expect(c.state.phase, SearchPhase.tooShort);
      c.onChanged('ri');
      expect(c.state.phase, SearchPhase.tooShort);
      expect(c.state.local, isEmpty);
      expect(api.searchCalls, 0);
    });

    testWidgets('whitespace does not count towards the minimum', (tester) async {
      final c = _ctrl(FakeFoodApi());
      addTearDown(c.dispose);
      c.onChanged('  ri  ');
      expect(c.state.phase, SearchPhase.tooShort);
      expect(c.state.query, 'ri');
    });

    testWidgets('3 characters: bundled results at once, still no network',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.onChanged('ric');
      expect(c.state.phase, SearchPhase.results);
      expect(c.state.local.map((h) => h.food.id), containsAll(['gen:1', 'gen:2']));
      expect(c.state.local.any((h) => h.food.id == 'gen:3'), isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(api.searchCalls, 0, reason: 'typing never calls the server');
      expect(c.state.remote, isEmpty);
    });

    testWidgets('no bundled hit and server off is the calm empty phase',
        (tester) async {
      final c = _ctrl(FakeFoodApi(), server: false);
      addTearDown(c.dispose);
      c.onChanged('zzzz');
      expect(c.state.phase, SearchPhase.empty);
    });

    testWidgets('no bundled hit with server on waits for a submit (results)',
        (tester) async {
      final c = _ctrl(FakeFoodApi());
      addTearDown(c.dispose);
      c.onChanged('zzzz');
      expect(c.state.phase, SearchPhase.results);
      expect(c.state.local, isEmpty);
    });

    testWidgets('an empty bundled table still answers (offline, no asset)',
        (tester) async {
      final c = _ctrl(FakeFoodApi(), table: GenericFoodTable.empty(), server: false);
      addTearDown(c.dispose);
      c.onChanged('rice');
      expect(c.state.phase, SearchPhase.empty);
    });
  });

  group('submit and debounce', () {
    testWidgets('the server is called at 600 ms, not before', (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      expect(c.state.phase, SearchPhase.loading);
      await tester.pump(const Duration(milliseconds: 599));
      expect(api.searchCalls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.searchCalls, 1);
      expect(api.lastQuery, 'rice');
      await tester.pump();
      expect(c.state.phase, SearchPhase.results);
      expect(c.state.remote.single.foodRef, 'off:111');
      expect(c.state.local, isNotEmpty, reason: 'bundled hits stay');
    });

    testWidgets('a second submit inside the window replaces the pending one',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 300));
      c.submit('rice bowl');
      await tester.pump(const Duration(milliseconds: 599));
      expect(api.searchCalls, 0, reason: 'the clock restarted at the 2nd submit');
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.searchCalls, 1);
      expect(api.lastQuery, 'rice bowl');
    });

    testWidgets('submit under 3 characters never calls the server',
        (tester) async {
      final api = FakeFoodApi();
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('ri');
      expect(c.state.phase, SearchPhase.tooShort);
      await tester.pump(const Duration(seconds: 2));
      expect(api.searchCalls, 0);
    });

    testWidgets('with the server flag off a submit makes no call',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api, server: false);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(seconds: 2));
      expect(api.searchCalls, 0);
      expect(c.state.phase, SearchPhase.results, reason: 'bundled still answer');
      expect(c.state.remote, isEmpty);
    });

    testWidgets('dispose cancels a pending submit', (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      c.submit('rice');
      c.dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(api.searchCalls, 0);
    });

    testWidgets('no matches anywhere is the empty phase', (tester) async {
      final api = FakeFoodApi(search: const []);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('zzzz');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(c.state.phase, SearchPhase.empty);
    });

    testWidgets('server results alone (no bundled hit) are results',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('zzzz');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(c.state.phase, SearchPhase.results);
      expect(c.state.remote, hasLength(1));
    });
  });

  group('last-results cache', () {
    testWidgets('the same query (any case, padded) costs no second call',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(api.searchCalls, 1);
      c.submit(' RICE ');
      await tester.pump(const Duration(seconds: 2));
      expect(api.searchCalls, 1);
      expect(c.state.remote.single.foodRef, 'off:111');
      expect(c.state.phase, SearchPhase.results);
    });

    testWidgets('typing the cached query again keeps the remote rows',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      c.onChanged('ric');
      expect(c.state.remote, isEmpty, reason: 'other query: no stale rows');
      c.onChanged('rice');
      expect(c.state.remote, hasLength(1));
    });

    testWidgets('a different query calls again and replaces the cache',
        (tester) async {
      final api = FakeFoodApi(search: const [_cand]);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      api.search = const [];
      c.submit('chicken');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(api.searchCalls, 2);
      expect(c.state.remote, isEmpty);
      // Going back to the first query is a miss now (only the LAST is kept).
      api.search = const [_cand];
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(api.searchCalls, 3);
    });

    testWidgets('a failure is not cached: the retry calls again',
        (tester) async {
      final api = FakeFoodApi(failure: FoodApiFailure.upstreamUnavailable);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      api.failure = null;
      api.search = const [_cand];
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(api.searchCalls, 2);
      expect(c.state.remote, hasLength(1));
    });
  });

  group('failure phases', () {
    Future<FoodSearchController> failing(
        WidgetTester tester, FoodApiFailure f, String q) async {
      final c = _ctrl(FakeFoodApi(failure: f));
      addTearDown(c.dispose);
      c.submit(q);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      return c;
    }

    testWidgets('feature-disabled is the calm notAvailable phase, not error',
        (tester) async {
      final c = await failing(tester, FoodApiFailure.featureDisabled, 'rice');
      expect(c.state.phase, SearchPhase.notAvailable);
      expect(c.state.rateLimited, isFalse);
    });

    testWidgets('source-not-configured is also notAvailable', (tester) async {
      final c = await failing(tester, FoodApiFailure.sourceNotConfigured, 'zzzz');
      expect(c.state.phase, SearchPhase.notAvailable);
    });

    testWidgets('upstream failure with bundled hits keeps the results phase',
        (tester) async {
      final c = await failing(tester, FoodApiFailure.upstreamUnavailable, 'rice');
      expect(c.state.phase, SearchPhase.results);
      expect(c.state.local, isNotEmpty);
      expect(c.state.rateLimited, isFalse);
    });

    testWidgets('upstream failure with nothing to show is the error phase',
        (tester) async {
      final c = await failing(tester, FoodApiFailure.upstreamUnavailable, 'zzzz');
      expect(c.state.phase, SearchPhase.error);
    });

    testWidgets('rate limited sets the flag, with and without bundled hits',
        (tester) async {
      final a = await failing(tester, FoodApiFailure.rateLimited, 'rice');
      expect(a.state.rateLimited, isTrue);
      expect(a.state.phase, SearchPhase.results);
      final b = await failing(tester, FoodApiFailure.rateLimited, 'zzzz');
      expect(b.state.rateLimited, isTrue);
      expect(b.state.phase, SearchPhase.error);
    });

    testWidgets('a later success clears the rate-limited flag', (tester) async {
      final api = FakeFoodApi(failure: FoodApiFailure.rateLimited);
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(c.state.rateLimited, isTrue);
      api.failure = null;
      api.search = const [_cand];
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(c.state.rateLimited, isFalse);
    });

    testWidgets('a response for a superseded query is ignored', (tester) async {
      final api = _HeldApi();
      final c = _ctrl(api);
      addTearDown(c.dispose);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.pending, hasLength(1));
      c.onChanged('chicken');
      api.pending.single.complete(const SearchResults([_cand]));
      await tester.pump();
      expect(c.state.query, 'chicken');
      expect(c.state.remote, isEmpty);
      // And the late rice answer was not cached as chicken's.
      c.submit('chicken');
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.searchCalls, 2);
    });

    testWidgets('a response after dispose does not throw', (tester) async {
      final api = _HeldApi();
      final c = _ctrl(api);
      c.submit('rice');
      await tester.pump(const Duration(milliseconds: 600));
      c.dispose();
      api.pending.single.complete(const SearchResults([_cand]));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  test('constants: minimum 3 characters and 600 ms default debounce', () {
    expect(FoodSearchController.minChars, 3);
    expect(_ctrl(FakeFoodApi()).debounce, const Duration(milliseconds: 600));
  });
}
