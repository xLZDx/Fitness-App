import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/injuries_page.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// The screen that makes a stored injury editable, and the reason it had to
/// exist at all.
///
/// `ProfileRepository.save()` had exactly two call sites, both inside
/// `features/onboarding/`. The one affordance meant to reach them — the
/// questionnaire tile on the profile page — routes to `/onboarding`, which
/// `resolveRedirect` bounces straight back to `/home` for anyone who has
/// onboarded. So no existing user could change a stored injury by any path,
/// which made the structured region undeliverable to every one of them.
///
/// These tests are therefore about the save reaching the repository, not only
/// about the widget rendering.

class _RecordingProfileRepo implements ProfileRepository {
  _RecordingProfileRepo(this._initial);

  UserProfile? _initial;
  final saved = <UserProfile>[];
  final _controller = StreamController<UserProfile?>.broadcast();

  @override
  Stream<UserProfile?> watch(String uid) async* {
    yield _initial;
    yield* _controller.stream;
  }

  @override
  UserProfile? cached(String uid) => _initial;

  @override
  Future<UserProfile?> load(String uid) async => _initial;

  @override
  Future<void> save(UserProfile profile) async {
    saved.add(profile);
    _initial = profile;
    _controller.add(profile);
  }

  @override
  Future<void> delete(String uid) async {}

  Future<void> dispose() => _controller.close();
}

const _user = AuthUser(uid: 'u1', displayName: 'U');

UserProfile _profileWith(List<Injury> injuries) => UserProfile(
      uid: 'u1',
      health: HealthHistory(injuries: injuries),
      completedAt: DateTime(2026, 1, 1),
    );

void main() {
  late _RecordingProfileRepo repo;

  tearDown(() => repo.dispose());

  Future<void> open(WidgetTester tester, List<Injury> injuries) async {
    repo = _RecordingProfileRepo(_profileWith(injuries));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(_user)),
        profileRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InjuriesPage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Injury lastSaved() => repo.saved.last.health.injuries.single;

  /// The Save button sits below the fold in a 800x600 test viewport and the
  /// list builds lazily, so it does not exist until scrolled to. Finding it
  /// without this fails as "0 widgets", which reads like a missing button
  /// rather than an unbuilt one.
  Future<Finder> saveButton(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byType(FilledButton),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    return find.byType(FilledButton);
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(await saveButton(tester));
    await tester.pumpAndSettle();
  }

  group('a stored injury', () {
    testWidgets('is listed with what the user actually typed', (tester) async {
      await open(tester, const [Injury(bodyPart: 'Left knee', type: 'meniscus')]);
      expect(find.text('Left knee'), findsOneWidget);
      expect(find.text('meniscus'), findsOneWidget);
    });

    testWidgets('gets a proposed region, pre-selected but not saved',
        (tester) async {
      await open(tester, const [Injury(bodyPart: 'Left knee', type: 'x')]);
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Knee'),
      );
      expect(chip.selected, isTrue,
          reason: 'suggestRegion proposes; nothing is written until Save');
      expect(repo.saved, isEmpty);
    });

    testWidgets('gets no proposal when it is none of the eight',
        (tester) async {
      await open(tester, const [Injury(bodyPart: 'rib', type: 'bruise')]);
      for (final label in ['Knee', 'Hip', 'Shoulder', 'Ankle']) {
        expect(
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected,
          isFalse,
          reason: 'forcing the nearest region onto a rib is a false claim',
        );
      }
      expect(find.textContaining('still needs an area'), findsOneWidget);
    });
  });

  group('saving', () {
    testWidgets('reaches the repository — the whole point of the screen',
        (tester) async {
      await open(tester, const [Injury(bodyPart: 'Left knee', type: 'x')]);
      await tapSave(tester);

      expect(repo.saved, hasLength(1));
      expect(lastSaved().region, InjuryRegion.knee);
    });

    testWidgets('keeps the words the user typed alongside the region',
        (tester) async {
      // S1b migrates by adding a region beside bodyPart, never replacing it,
      // so a mapping that turns out wrong is still undoable from the original.
      await open(tester, const [Injury(bodyPart: 'левое колено', type: 'x')]);
      await tapSave(tester);

      expect(lastSaved().bodyPart, 'левое колено');
      expect(lastSaved().region, InjuryRegion.knee);
    });

    testWidgets('declining every region is stored as a decision',
        (tester) async {
      // Without this the app cannot tell "nobody has looked at it" from "no
      // region fits", and would ask about a rib injury on every load forever.
      await open(tester, const [Injury(bodyPart: 'rib', type: 'bruise')]);
      await tester.tap(find.widgetWithText(ChoiceChip, 'None of these'));
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(lastSaved().confirmed, isTrue);
      expect(lastSaved().region, isNull);
      expect(lastSaved().isResolved, isTrue);
    });

    testWidgets('choosing a different region overrides the proposal',
        (tester) async {
      await open(tester, const [Injury(bodyPart: 'Left knee', type: 'x')]);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Hip'));
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(lastSaved().region, InjuryRegion.hip);
    });

    testWidgets('is disabled until something changes', (tester) async {
      await open(tester, const [
        Injury(bodyPart: 'knee', type: 'x', region: InjuryRegion.knee),
      ]);
      final button = tester.widget<FilledButton>(await saveButton(tester));
      expect(button.onPressed, isNull);
    });

    testWidgets('drops a blank row instead of refusing the whole save',
        (tester) async {
      await open(tester, const [Injury(bodyPart: 'knee', type: 'x')]);
      // Scrolling to Save brings "Add an injury" into view with it -- it sits
      // directly above. Tapped by its label rather than by type: the button is
      // an OutlinedButton.icon, whose factory returns a private subclass, and
      // find.byType matches the exact runtime type only.
      await saveButton(tester);
      await tester.tap(find.text('Add an injury'));
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(repo.saved.last.health.injuries, hasLength(1));
    });
  });

  group('removing', () {
    testWidgets('an injury is gone from the saved list', (tester) async {
      await open(tester, const [
        Injury(bodyPart: 'knee', type: 'x'),
        Injury(bodyPart: 'shoulder', type: 'y'),
      ]);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(lastSaved().bodyPart, 'shoulder');
    });
  });

  group('an empty list', () {
    testWidgets('says so rather than rendering nothing', (tester) async {
      await open(tester, const []);
      expect(find.textContaining("haven't listed any injuries"), findsOneWidget);
    });
  });
}
