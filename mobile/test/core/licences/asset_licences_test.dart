import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/core/licences/asset_licences.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/licences/licences_page.dart';

import '../../helpers/test_app.dart';

/// Guards the attribution surface.
///
/// The bundled content ships under licences that require credit to be visible
/// to the user. Before this existed there was no credits screen at all — no
/// `showLicensePage`, no `LicenseRegistry` entry, nothing — which is a licence
/// breach rather than a missing nicety, so the checks here are about the
/// obligation being met, not about cosmetics.
void main() {
  group('attribution data', () {
    test('is not empty', () {
      expect(kAssetAttributions, isNotEmpty);
    });

    test('every entry is fully credited', () {
      for (final a in kAssetAttributions) {
        expect(a.what.trim(), isNotEmpty, reason: 'what is missing');
        expect(a.author.trim(), isNotEmpty, reason: '${a.what}: no author');
        expect(a.licence.trim(), isNotEmpty, reason: '${a.what}: no licence');
        expect(a.url.trim(), isNotEmpty, reason: '${a.what}: no source');
        expect(a.url, startsWith('http'), reason: '${a.what}: unusable source');
        expect(a.note?.trim(), isNot(''),
            reason: '${a.what}: blank note reads as an oversight');
      }
    });

    test('the rendered body names author, licence and source', () {
      for (final body in debugLicenceBodies()) {
        expect(body, contains('Author:'));
        expect(body, contains('Licence:'));
        expect(body, contains('Source:'));
      }
    });

    test('publishing into the registry yields one entry per attribution',
        () async {
      // A fresh registry per test run; addLicense is global, so this asserts on
      // the delta rather than the absolute count.
      final before = await LicenseRegistry.licenses.length;
      registerAssetLicences();
      final after = await LicenseRegistry.licenses.toList();
      expect(after.length, before + kAssetAttributions.length);
      final packages = after.expand((e) => e.packages).toSet();
      for (final a in kAssetAttributions) {
        expect(packages, contains(a.what));
      }
    });
  });

  group('licences page', () {
    testWidgets('renders every credit and the package-licences entry point',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LicencesPage(),
      ));
      await tester.pumpAndSettle();

      for (final a in kAssetAttributions) {
        expect(find.text(a.what), findsOneWidget);
        expect(find.text(a.licence), findsOneWidget);
      }
      expect(find.byKey(const Key('licences-open-package-licences')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('reachability', () {
    // Mechanical, because "we shipped the page but nothing links to it" is the
    // way a credits screen fails in practice.
    test('settings links to it and startup registers the licences', () {
      final settings =
          File('lib/features/settings/settings_page.dart').readAsStringSync();
      expect(settings, contains("'/licences'"));

      final router =
          File('lib/core/router/app_router.dart').readAsStringSync();
      expect(router, contains("path: '/licences'"));
      expect(router, contains('LicencesPage'));

      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('registerAssetLicences()'));
    });

    test('the page does not require a login', () {
      // Attribution behind a sign-in wall is not attribution.
      final router =
          File('lib/core/router/app_router.dart').readAsStringSync();
      final publicLine = router
          .split('\n')
          .firstWhere((l) => l.contains('_publicPaths = '));
      expect(publicLine, contains('/licences'));
    });
  });
}
