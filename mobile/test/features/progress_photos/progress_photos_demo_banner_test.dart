import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/progress_photos_page.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';

/// M0: photos captured through the mock repository live in one instance's
/// in-memory list and vanish on restart, with nothing on the page saying so.
/// A user who captured a "before" photo, closed the app, and returned to
/// find it gone would reasonably read that as data loss.

class _NeverPersists implements ProgressPhotosRepository {
  const _NeverPersists();
  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);
  @override
  Future<ProgressPhoto> capture() async => throw UnimplementedError();
  @override
  Future<void> delete(String id) async {}
}

Widget _host({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProgressPhotosPage(),
      ),
    );

void main() {
  testWidgets('the demo banner shows while the mock repository is bound',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('not saved to your account'), findsOneWidget);
  });

  testWidgets('the banner is gone once a real repository is bound',
      (tester) async {
    await tester.pumpWidget(_host(overrides: [
      progressPhotosRepositoryProvider.overrideWithValue(_NeverPersists()),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('not saved to your account'), findsNothing);
  });

  /// The page promised "Photos are encrypted on your device with a key that
  /// never leaves the phone" unconditionally, while the only repository bound
  /// was the mock: no bytes, no key, no cipher call. `AesPhotoCipher` is real
  /// and correct, and has no caller.
  ///
  /// The promise is not deleted, because it is the promise the feature is
  /// being built to keep. It is gated on the same flag as the banner above, so
  /// that binding a real repository is the single act that makes it reappear —
  /// no second edit, and no way to ship the storage layer while the claim
  /// stays switched off.
  testWidgets('the encryption promise is withheld while the mock is bound',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('encrypted'), findsNothing);
  });

  testWidgets('the encryption promise returns with a real repository',
      (tester) async {
    await tester.pumpWidget(_host(overrides: [
      progressPhotosRepositoryProvider.overrideWithValue(_NeverPersists()),
    ]));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('encrypted on your device'),
      findsOneWidget,
    );
  });
}
