import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/demo_features.dart';

void main() {
  group('demoFeaturesEnabledFor', () {
    test('non-release builds always enable demo features', () {
      expect(demoFeaturesEnabledFor(isRelease: false, definedFlag: false), isTrue);
      expect(demoFeaturesEnabledFor(isRelease: false, definedFlag: true), isTrue);
    });

    test('release builds enable them only with the explicit define', () {
      expect(demoFeaturesEnabledFor(isRelease: true, definedFlag: false), isFalse);
      expect(demoFeaturesEnabledFor(isRelease: true, definedFlag: true), isTrue);
    });
  });

  test('kDemoFeaturesEnabled is the function applied to the real constants', () {
    expect(
      kDemoFeaturesEnabled,
      demoFeaturesEnabledFor(
        isRelease: kReleaseMode,
        definedFlag: const bool.fromEnvironment('DEMO_FEATURES'),
      ),
    );
  });
}
