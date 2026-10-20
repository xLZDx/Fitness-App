// T98 food_api_test (FOOD-24): callable error mapping to the closed failure
// set, calm "not available yet" classification, response parsers and the
// scriptable fake. Expected values are written by hand from the server
// contract, not read back from the code under test.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:flutter_test/flutter_test.dart';

FoodApiException _map(String code, [String? message]) => mapFoodCallableError(
    FirebaseFunctionsException(code: code, message: message ?? ''));

void main() {
  group('mapFoodCallableError: slugs', () {
    test('failed-precondition feature-disabled is the calm featureDisabled', () {
      final e = _map('failed-precondition', 'feature-disabled');
      expect(e.failure, FoodApiFailure.featureDisabled);
      expect(e.slug, 'feature-disabled');
      expect(e.isNotAvailableYet, isTrue);
      expect(e.retriable, isFalse, reason: 'feature-disabled is not retried');
    });

    test('source-not-configured is treated like feature-off, not retried', () {
      final e = _map('failed-precondition', 'source-not-configured');
      expect(e.failure, FoodApiFailure.sourceNotConfigured);
      expect(e.isNotAvailableYet, isTrue);
      expect(e.retriable, isFalse);
    });

    test('the slug wins over the transport code', () {
      // A feature-disabled slug on an unrelated code is still feature-off.
      expect(_map('internal', 'feature-disabled').failure,
          FoodApiFailure.featureDisabled);
    });

    test('rate-limited and upstream-unavailable slugs are retriable', () {
      final r = _map('resource-exhausted', 'rate-limited');
      expect(r.failure, FoodApiFailure.rateLimited);
      expect(r.retriable, isTrue);
      expect(r.isNotAvailableYet, isFalse);
      final u = _map('unavailable', 'upstream-unavailable');
      expect(u.failure, FoodApiFailure.upstreamUnavailable);
      expect(u.retriable, isTrue);
    });

    test('invalid-barcode and invalid-query map to invalidInput, not retried',
        () {
      for (final s in ['invalid-barcode', 'invalid-query']) {
        final e = _map('invalid-argument', s);
        expect(e.failure, FoodApiFailure.invalidInput, reason: s);
        expect(e.retriable, isFalse, reason: s);
        expect(e.slug, s);
      }
    });
  });

  group('mapFoodCallableError: codes without a known slug', () {
    test('code table', () {
      const table = {
        'resource-exhausted': FoodApiFailure.rateLimited,
        'invalid-argument': FoodApiFailure.invalidInput,
        'unauthenticated': FoodApiFailure.notAllowed,
        'permission-denied': FoodApiFailure.notAllowed,
        'unavailable': FoodApiFailure.upstreamUnavailable,
        'deadline-exceeded': FoodApiFailure.upstreamUnavailable,
        'internal': FoodApiFailure.upstreamUnavailable,
        'aborted': FoodApiFailure.upstreamUnavailable,
        'not-found': FoodApiFailure.unknown,
        'cancelled': FoodApiFailure.unknown,
      };
      table.forEach((code, expected) {
        expect(_map(code).failure, expected, reason: code);
      });
    });

    test('not-allowed is not retriable; unknown is', () {
      expect(_map('unauthenticated').retriable, isFalse);
      expect(_map('not-found').retriable, isTrue);
    });

    test('free text is never kept as a slug (D-67)', () {
      final e = _map('internal',
          'Error: ECONNRESET for user u1 at https://example.com/x?q=chicken');
      expect(e.slug, isNull);
      expect(e.toString(), isNot(contains('chicken')));
      expect(e.toString(), isNot(contains('ECONNRESET')));
    });

    test('a slug longer than 60 characters or with uppercase is dropped', () {
      expect(_map('internal', 'a' * 61).slug, isNull);
      expect(_map('internal', 'a' * 60).slug, 'a' * 60);
      expect(_map('internal', 'Feature-Disabled').slug, isNull);
      expect(_map('failed-precondition', 'Feature-Disabled').failure,
          FoodApiFailure.unknown);
    });

    test('empty message keeps the code mapping and a null slug', () {
      final e = mapFoodCallableError(
          FirebaseFunctionsException(code: 'unavailable', message: ''));
      expect(e.failure, FoodApiFailure.upstreamUnavailable);
      expect(e.slug, isNull);
    });
  });

  group('parseMealAnalysis', () {
    Map<String, dynamic> item({
      Object? name = 'Rice',
      Object? grams = const {'low': 100, 'mid': 150, 'high': 200},
      Object? per100g = const {
        'kcal': 130,
        'proteinG': 2.7,
        'carbsG': 28,
        'fatG': 0.3
      },
      Object? source = 'usda_fdc',
      Object? sourceRef,
      Object? matchQuality = 'close',
      Object? confidence = 0.8,
      Object? checkCodes,
    }) =>
        {
          'name': name,
          'grams': grams,
          'per100g': per100g,
          'source': source,
          'sourceRef': sourceRef,
          'matchQuality': matchQuality,
          'confidence': confidence,
          'checkCodes': checkCodes,
        };

    test('a full item keeps source, ref, grams range and confidence', () {
      final m = parseMealAnalysis({
        'mealName': '  Rice bowl ',
        'entryConfidence': 'medium',
        'items': [item(sourceRef: '168878', checkCodes: ['portionUnclear'])],
        'assumptions': ['cookingMethod'],
        'model': {'id': 'gemini', 'version': '2'},
      });
      expect(m.mealName, 'Rice bowl');
      expect(m.confidence, EntryConfidence.medium);
      expect(m.items, hasLength(1));
      final i = m.items.single;
      expect(i.name, 'Rice');
      expect(i.grams, MacroRange(100, 150, 200));
      expect(i.per100g!.kcal, 130);
      expect(i.source, FoodSource.usda);
      expect(i.foodRef, 'usda:168878');
      expect(i.matchQuality, MatchQuality.close);
      expect(i.confidence, 0.8);
      expect(i.checkCodes, [CheckCode.portionUnclear]);
      expect(m.assumptions, [CheckCode.cookingMethod]);
      expect(m.model!.id, 'gemini');
    });

    test('garbage body yields an empty, low-confidence analysis', () {
      final m = parseMealAnalysis({'items': 'nope', 'entryConfidence': 7});
      expect(m.items, isEmpty);
      expect(m.mealName, '');
      expect(m.confidence, EntryConfidence.low);
      expect(m.model, isNull);
    });

    test('items without a name or grams map are skipped', () {
      final m = parseMealAnalysis({
        'items': [
          item(name: ''),
          item(name: '   '),
          item(name: 5),
          item(grams: 'x'),
          'not a map',
          item(name: 'Kept'),
        ]
      });
      expect(m.items.map((i) => i.name), ['Kept']);
    });

    test('unknown source falls back to the model estimate; unknown codes drop',
        () {
      final m = parseMealAnalysis({
        'items': [
          item(source: 'made_up', checkCodes: ['bogus', 'hiddenIngredients'])
        ]
      });
      expect(m.items.single.source, FoodSource.llmEstimate);
      expect(m.items.single.checkCodes, [CheckCode.hiddenIngredients]);
    });

    test('per100g with a missing, negative or non-finite macro is null', () {
      for (final bad in <Object?>[
        {'kcal': 100, 'proteinG': 1, 'carbsG': 1},
        {'kcal': -1, 'proteinG': 1, 'carbsG': 1, 'fatG': 1},
        {'kcal': double.nan, 'proteinG': 1, 'carbsG': 1, 'fatG': 1},
        {'kcal': '100', 'proteinG': 1, 'carbsG': 1, 'fatG': 1},
        null,
      ]) {
        final m = parseMealAnalysis({
          'items': [item(per100g: bad)]
        });
        expect(m.items.single.per100g, isNull, reason: '$bad');
        expect(m.items.single.toFoodItem(), isNull,
            reason: 'never written as zeros');
      }
    });

    test('at most 30 items are kept', () {
      final m = parseMealAnalysis({
        'items': [for (var i = 0; i < 40; i++) item(name: 'f$i')]
      });
      expect(m.items, hasLength(FoodEntry.maxItems));
    });

    test('negative confidence is treated as zero', () {
      final m = parseMealAnalysis({
        'items': [item(confidence: -0.5)]
      });
      expect(m.items.single.confidence, 0);
    });
  });

  group('AnalysedItem', () {
    const per = Per100g(kcal: 100, proteinG: 1, carbsG: 2, fatG: 3);
    AnalysedItem mk(String name, FoodSource s, {String? ref}) => AnalysedItem(
          name: name,
          grams: MacroRange.exact(100),
          per100g: per,
          source: s,
          sourceRef: ref,
          matchQuality: MatchQuality.none,
          confidence: 0.5,
        );

    test('foodRef prefixes', () {
      expect(mk('x', FoodSource.off, ref: '123').foodRef, 'off:123');
      expect(mk('x', FoodSource.usda, ref: '9').foodRef, 'usda:9');
    });

    test('estimates get llm:<slug>, even when a ref is present', () {
      expect(mk('Fried Rice & Egg!', FoodSource.llmEstimate).foodRef,
          'llm:fried-rice-egg');
      expect(mk('Plov', FoodSource.llmEstimate, ref: '5').foodRef, 'llm:plov');
    });

    test('a name with no latin letters or digits becomes llm:item', () {
      expect(mk('Борщ', FoodSource.llmEstimate).foodRef, 'llm:item');
    });

    test('off without a ref falls back to llm slug, never "off:"', () {
      expect(mk('Bar', FoodSource.off).foodRef, 'llm:bar');
      expect(mk('Bar', FoodSource.off, ref: '').foodRef, 'llm:bar');
    });

    test('toFoodItem truncates names to 80 characters', () {
      final f = mk('a' * 120, FoodSource.llmEstimate).toFoodItem()!;
      expect(f.name.length, FoodItem.maxNameLength);
      expect(f.per100g, per);
      expect(f.source, FoodSource.llmEstimate);
    });
  });

  group('parseCandidate and parseBarcodeLookup', () {
    Map<String, dynamic> cand({
      String source = 'open_food_facts',
      Object? completeness,
      Object? brand = 'Acme',
      Object? servingG = 30,
    }) =>
        {
          'foodRef': 'off:123',
          'name': 'Bar',
          'brand': brand,
          'source': source,
          'completeness': completeness,
          'servingG': servingG,
          'per100g': {'kcal': 400, 'proteinG': 10, 'carbsG': 50, 'fatG': 15},
        };

    test('a complete candidate', () {
      final c = parseCandidate(cand())!;
      expect(c.foodRef, 'off:123');
      expect(c.brand, 'Acme');
      expect(c.servingG, 30);
      expect(c.complete, isTrue);
      expect(c.source, FoodSource.off);
    });

    test('partial completeness is flagged', () {
      expect(parseCandidate(cand(completeness: 'partial'))!.complete, isFalse);
    });

    test('empty brand becomes null; negative serving becomes null', () {
      final c = parseCandidate(cand(brand: '', servingG: -4))!;
      expect(c.brand, isNull);
      expect(c.servingG, isNull);
    });

    test('model estimates and user sources are refused as candidates', () {
      expect(parseCandidate(cand(source: 'llm_estimate')), isNull);
      expect(parseCandidate(cand(source: 'user')), isNull);
      expect(parseCandidate(cand(source: 'nonsense')), isNull);
    });

    test('non-map and incomplete rows give null', () {
      expect(parseCandidate('x'), isNull);
      expect(parseCandidate({'name': 'x'}), isNull);
    });

    test('barcode: found builds the ref from the SCANNED barcode', () {
      final l = parseBarcodeLookup({
        'found': true,
        'source': 'open_food_facts',
        'dataQuality': 'partial',
        'product': {
          'name': 'Bar',
          'brand': 'Acme',
          'servingG': 25,
          'per100g': {'kcal': 400, 'proteinG': 10, 'carbsG': 50, 'fatG': 15},
        },
      }, '4006381333931');
      expect(l.found, isTrue);
      expect(l.candidate!.foodRef, 'off:4006381333931');
      expect(l.candidate!.complete, isFalse);
      expect(l.candidate!.servingG, 25);
    });

    test('barcode: not found, bad source or unusable per100g are notFound', () {
      expect(parseBarcodeLookup({'found': false}, '1').found, isFalse);
      expect(
          parseBarcodeLookup({
            'found': true,
            'source': 'user',
            'product': {'name': 'x', 'per100g': {}}
          }, '1')
              .found,
          isFalse);
      expect(
          parseBarcodeLookup({
            'found': true,
            'source': 'usda_fdc',
            'product': {
              'name': 'x',
              'per100g': {'kcal': 1}
            }
          }, '1')
              .found,
          isFalse);
    });
  });

  group('parseLabelReading', () {
    test('values, serving and closed codes', () {
      final r = parseLabelReading({
        'per100g': {'kcal': 250, 'proteinG': 5, 'carbsG': 30, 'fatG': 10},
        'perServing': {'kcal': 125, 'proteinG': 2.5, 'carbsG': 15, 'fatG': 5},
        'servingG': 50,
        'checkCodes': ['labelAmbiguous', 'free text'],
      });
      expect(r.per100g!.kcal, 250);
      expect(r.perServing!.kcal, 125);
      expect(r.servingG, 50);
      expect(r.checkCodes, [CheckCode.labelAmbiguous]);
    });

    test('nothing usable gives nulls, not zeros', () {
      final r = parseLabelReading({'per100g': {'kcal': 1}});
      expect(r.per100g, isNull);
      expect(r.perServing, isNull);
      expect(r.servingG, isNull);
    });
  });

  group('FakeFoodApi', () {
    test('counts calls and returns scripted values', () async {
      final api = FakeFoodApi(search: const []);
      await api.searchFoods('abc', languageCode: 'en');
      await api.searchFoods('abcd', languageCode: 'en');
      expect(api.searchCalls, 2);
      expect(api.lastQuery, 'abcd');
      expect((await api.lookupBarcode('1')).found, isFalse);
      expect(api.barcodeCalls, 1);
      final meal = await api.analyzeMeal(text: 'x', languageCode: 'en');
      expect(meal.items, isEmpty);
      expect(api.analyzeCalls, 1);
      expect((await api.parseLabel(
              imageBase64: 'x', mimeType: 'image/jpeg', languageCode: 'en'))
          .per100g, isNull);
      expect(api.labelCalls, 1);
    });

    test('failure makes every call throw the closed exception, still counted',
        () async {
      final api = FakeFoodApi(failure: FoodApiFailure.featureDisabled);
      await expectLater(
          api.analyzeMeal(text: 'x', languageCode: 'en'),
          throwsA(isA<FoodApiException>().having(
              (e) => e.isNotAvailableYet, 'isNotAvailableYet', isTrue)));
      await expectLater(
          api.searchFoods('abc', languageCode: 'en'), throwsA(isA<FoodApiException>()));
      await expectLater(api.lookupBarcode('1'), throwsA(isA<FoodApiException>()));
      await expectLater(
          api.parseLabel(imageBase64: 'x', mimeType: 'm', languageCode: 'en'),
          throwsA(isA<FoodApiException>()));
      expect(api.analyzeCalls + api.searchCalls + api.barcodeCalls + api.labelCalls,
          4);
    });
  });
}
