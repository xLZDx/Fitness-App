import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/features/account_deletion/account_deletion_page.dart';
import 'package:fitness_app/features/account_deletion/data/account_deletion_service.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/app_buttons.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';

/// L0b — the confirmation surface for the one action in this app that is
/// genuinely irreversible: it cancels a real subscription and permanently
/// erases stored health data. Type-to-confirm, not a two-tap dialog a thumb
/// can dismiss past.

class _FakeAuthRepo implements AuthRepository {
  bool signedOut = false;
  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(
        signedOut ? null : const AuthUser(uid: 'u1', displayName: 'U'),
      );
  @override
  AuthUser? get currentUser =>
      signedOut ? null : const AuthUser(uid: 'u1', displayName: 'U');
  @override
  Future<AuthUser> signInAnonymously() async => throw UnimplementedError();
  @override
  Future<SignInResult> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

Widget _host(
  MockAccountDeletionService service, {
  _FakeAuthRepo? authRepo,
}) {
  final router = GoRouter(
    initialLocation: '/delete-account',
    routes: [
      GoRoute(
        path: '/delete-account',
        builder: (_, __) => const AccountDeletionPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('login-arrived')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      accountDeletionServiceProvider.overrideWithValue(service),
      if (authRepo != null) authRepositoryProvider.overrideWithValue(authRepo),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('lists the concrete consequences, not a vague warning',
      (tester) async {
    await tester.pumpWidget(_host(MockAccountDeletionService()));
    await tester.pumpAndSettle();

    expect(find.textContaining('subscription is cancelled'), findsOneWidget);
    expect(find.textContaining('injury list are permanently erased'),
        findsOneWidget);
    expect(find.textContaining('workout history'), findsOneWidget);
    expect(find.textContaining('no way to recover'), findsOneWidget);
  });

  testWidgets('the delete button is disabled until the confirm word is typed',
      (tester) async {
    await tester.pumpWidget(_host(MockAccountDeletionService()));
    await tester.pumpAndSettle();

    // `AppPrimaryButton`, not the `FilledButton` it renders: the key is on the
    // component, and asking about the component's own `onPressed` is the
    // contract that matters — the inner button is an implementation detail
    // that also gets nulled by `loading`, which this test is not about.
    AppPrimaryButton button() => tester.widget<AppPrimaryButton>(
          find.byKey(const Key('account-deletion-confirm-button')),
        );
    expect(button().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('account-deletion-confirm-field')),
      'delete', // wrong case
    );
    await tester.pump();
    expect(button().onPressed, isNull,
        reason: 'the confirm word must match exactly, not case-insensitively '
            '-- a near-miss is not the same as a deliberate confirmation');

    await tester.enterText(
      find.byKey(const Key('account-deletion-confirm-field')),
      kAccountDeletionConfirmWord,
    );
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('confirming calls the service exactly once', (tester) async {
    final service = MockAccountDeletionService();
    await tester.pumpWidget(_host(service, authRepo: _FakeAuthRepo()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('account-deletion-confirm-field')),
      kAccountDeletionConfirmWord,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-deletion-confirm-button')));
    await tester.pumpAndSettle();

    expect(service.callCount, 1);
  });

  testWidgets('success routes to /login, replacing the stack', (tester) async {
    final service = MockAccountDeletionService();
    final authRepo = _FakeAuthRepo();
    await tester.pumpWidget(_host(service, authRepo: authRepo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('account-deletion-confirm-field')),
      kAccountDeletionConfirmWord,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-deletion-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.text('login-arrived'), findsOneWidget);
    expect(authRepo.signedOut, isTrue,
        reason: 'the local client must sign itself out rather than wait for '
            'a future token refresh to discover the account is gone');
  });

  testWidgets('failure shows an error and stays on the page, ready to retry',
      (tester) async {
    final service = MockAccountDeletionService()
      ..failWith = const AccountDeletionException('network is down');
    await tester.pumpWidget(_host(service, authRepo: _FakeAuthRepo()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('account-deletion-confirm-field')),
      kAccountDeletionConfirmWord,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('account-deletion-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(AccountDeletionPage), findsOneWidget,
        reason: 'a failed deletion must not navigate away -- the account '
            'still exists and the user needs to be able to try again');
  });
}
