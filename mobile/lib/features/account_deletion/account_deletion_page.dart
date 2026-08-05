import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/glass.dart';
import '../onboarding/widgets/inputs.dart';
import 'state/account_deletion_providers.dart';

const String kAccountDeletionConfirmWord = 'DELETE';

/// L0b — the confirmation surface for an irreversible action.
///
/// Type-to-confirm, not a two-tap dialog. This is the one flow in the app
/// that cancels a real subscription and permanently erases stored health
/// data (injuries, workout history) with no way back — a dialog a thumb can
/// dismiss-tap past is not enough friction for that, and the [Injury]
/// screening this app builds around only means something if the underlying
/// account is not casually deletable.
class AccountDeletionPage extends ConsumerStatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  ConsumerState<AccountDeletionPage> createState() =>
      _AccountDeletionPageState();
}

class _AccountDeletionPageState extends ConsumerState<AccountDeletionPage> {
  // A plain field, not a TextEditingController -- GlassTextField wraps a
  // TextFormField with `initialValue:`, seeded once rather than driven
  // continuously, so the parent tracking its own copy via `onChanged` is the
  // pattern the rest of the app already uses (injuries_page.dart's
  // per-injury fields). A controller here would have nothing to attach to.
  String _typed = '';
  bool get _confirmed => _typed.trim() == kAccountDeletionConfirmWord;

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    await ref.read(accountDeletionActionProvider.notifier).deleteAccount();
    if (!mounted) return;

    final result = ref.read(accountDeletionActionProvider);
    result.when(
      data: (_) {
        // The account no longer exists. There is nothing left in this stack
        // to pop back to, so this replaces it outright rather than pushing
        // -- a hardware back button must not be able to return here.
        GoRouter.of(context).go('/login');
      },
      loading: () {},
      error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountdeletionFailed('$e'))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(accountDeletionActionProvider);
    final loading = state.isLoading;

    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.accountdeletionTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 40),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: theme.colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.accountdeletionCannotBeUndone,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ConsequenceLine(l10n.accountdeletionConsequenceSubscription),
                _ConsequenceLine(l10n.accountdeletionConsequenceHealthData),
                _ConsequenceLine(l10n.accountdeletionConsequenceHistory),
                _ConsequenceLine(l10n.accountdeletionConsequenceNoRecovery),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FieldLabel(l10n.accountdeletionTypeToConfirm(
            kAccountDeletionConfirmWord,
          )),
          GlassTextField(
            key: const Key('account-deletion-confirm-field'),
            value: _typed,
            onChanged: (v) => setState(() => _typed = v),
            hint: kAccountDeletionConfirmWord,
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('account-deletion-confirm-button'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: !_confirmed || loading ? null : _delete,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(l10n.accountdeletionDeleteMyAccount),
          ),
        ],
      ),
    );
  }
}

class _ConsequenceLine extends StatelessWidget {
  const _ConsequenceLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: theme.textTheme.bodyMedium),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
