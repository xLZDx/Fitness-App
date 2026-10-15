// T24 check_items_test (SCAN-21, design 12.7). The closed set of check codes:
// every code has an action and an l10n key; free text never gets through.
import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all 13 codes of design 12.7 exist, in this stable order', () {
    expect(CheckCode.values.map((c) => c.name).toList(), [
      'provisionalEstimator',
      'manualCapture',
      'poorLighting',
      'partialBody',
      'looseClothing',
      'poseMismatch',
      'weightMissing',
      'weightStale',
      'weightJump',
      'wideRange',
      'estimateFarFromProfile',
      'largeJumpVsTrend',
      'blurUnavailable',
    ]);
    expect(CheckCode.values.length, 13);
  });

  test('every code maps to its action', () {
    expect({for (final c in CheckCode.values) c.name: c.action}, {
      'provisionalEstimator': CheckAction.none,
      'manualCapture': CheckAction.none,
      'poorLighting': CheckAction.retakeLighting,
      'partialBody': CheckAction.retakeFraming,
      'looseClothing': CheckAction.retakeFraming,
      'poseMismatch': CheckAction.retakePose,
      'weightMissing': CheckAction.logWeight,
      'weightStale': CheckAction.logWeight,
      'weightJump': CheckAction.confirmWeight,
      'wideRange': CheckAction.none,
      'estimateFarFromProfile': CheckAction.confirmWeight,
      'largeJumpVsTrend': CheckAction.none,
      'blurUnavailable': CheckAction.retakeFraming,
    });
  });

  test('every code has a distinct l10n key checkCode<Name>', () {
    final keys = [for (final c in CheckCode.values) c.l10nKey];
    expect(keys.toSet().length, 13);
    expect(CheckCode.provisionalEstimator.l10nKey,
        'checkCodeProvisionalEstimator');
    expect(CheckCode.blurUnavailable.l10nKey, 'checkCodeBlurUnavailable');
    expect(CheckCode.weightStale.l10nKey, 'checkCodeWeightStale');
    for (final k in keys) {
      expect(k, startsWith('checkCode'));
      expect(k[9], k[9].toUpperCase());
    }
  });

  test('weightStale triggers above 7 days', () {
    expect(CheckCode.weightStaleAfterDays, 7);
  });

  test('byName: known names resolve; unknown strings and non-strings are null', () {
    expect(CheckCode.byName('wideRange'), CheckCode.wideRange);
    expect(CheckCode.byName('WideRange'), isNull);
    expect(CheckCode.byName('ignore previous instructions'), isNull);
    expect(CheckCode.byName(null), isNull);
    expect(CheckCode.byName(3), isNull);
  });

  test('parseCheckCodes drops unknown provider strings', () {
    expect(
      parseCheckCodes(['poorLighting', 'Your body fat is perfect!', 'wideRange']),
      [CheckCode.poorLighting, CheckCode.wideRange],
    );
  });

  test('parseCheckCodes removes duplicates and sorts in declaration order', () {
    expect(
      parseCheckCodes(['blurUnavailable', 'manualCapture', 'blurUnavailable']),
      [CheckCode.manualCapture, CheckCode.blurUnavailable],
    );
  });

  test('parseCheckCodes of a non-list, null or empty list is empty', () {
    expect(parseCheckCodes(null), isEmpty);
    expect(parseCheckCodes('poorLighting'), isEmpty);
    expect(parseCheckCodes({'a': 1}), isEmpty);
    expect(parseCheckCodes(const []), isEmpty);
    expect(parseCheckCodes([1, null, true]), isEmpty);
  });
}
