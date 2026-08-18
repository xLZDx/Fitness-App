import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/social_feed/data/social_feed_repository.dart';
import 'package:fitness_app/features/social_feed/social_feed_page.dart';
import 'package:fitness_app/features/social_feed/state/social_feed_providers.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';

/// G2.1b-i: the like heart was one of five `IconButton`s with no [tooltip]
/// at all -- not a wrong label, no label. Screen-reader-invisible in both
/// its states. This proves the accessible name reaches BOTH the unliked and
/// the liked state, not just that a `tooltip:` argument now exists in the
/// source.
class _FakeAuthRepo implements AuthRepository {
  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(const AuthUser(uid: 'me', displayName: 'Me'));
  @override
  AuthUser? get currentUser => const AuthUser(uid: 'me', displayName: 'Me');
  @override
  Future<AuthUser> signInAnonymously() async => throw UnimplementedError();
  @override
  Future<SignInResult> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async {}
}

void main() {
  Future<AppLocalizations> pump(WidgetTester t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        socialFeedRepositoryProvider
            .overrideWithValue(MockSocialFeedRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SocialFeedPage(),
      ),
    ));
    await t.pumpAndSettle();

    // `authUserProvider` is only ever `ref.read`, never `ref.watch`, inside
    // the like handler -- nothing on this page creates it during build. In
    // the shipped app an ancestor auth gate already watches it before a
    // signed-in-only page is reachable, so it is warm by the time a real tap
    // lands. Nothing here does that, so the handler's `ref.read` would land
    // on the stream's not-yet-resolved first tick and silently no-op. Warm
    // it explicitly rather than let the test pass by accident of timing.
    final container =
        ProviderScope.containerOf(t.element(find.byType(SocialFeedPage)));
    container.read(authUserProvider);
    await t.pump();

    return AppLocalizations.of(t.element(find.byType(SocialFeedPage)));
  }

  testWidgets('unliked posts announce "Like", not nothing', (t) async {
    final l10n = await pump(t);
    // The seed has two posts, neither liked by 'me'.
    expect(find.byTooltip(l10n.socialfeedLike), findsNWidgets(2));
    expect(find.byTooltip(l10n.socialfeedUnlike), findsNothing);
  });

  testWidgets('tapping it flips the tooltip to "Unlike", live', (t) async {
    final l10n = await pump(t);
    await t.tap(find.byTooltip(l10n.socialfeedLike).first);
    await t.pumpAndSettle();

    expect(find.byTooltip(l10n.socialfeedUnlike), findsOneWidget,
        reason: 'the accessible name must track state, not just exist once '
            'at construction');
    expect(find.byTooltip(l10n.socialfeedLike), findsOneWidget,
        reason: 'the other, still-unliked post keeps its own label');
  });
}
