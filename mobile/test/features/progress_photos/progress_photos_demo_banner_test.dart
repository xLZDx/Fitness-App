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
}
