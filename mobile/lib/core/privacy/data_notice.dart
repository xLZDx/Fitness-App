import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/state/auth_providers.dart';
import '../config/body_scan_flags.dart';

/// First-use data notice (design s20.1 point 6, D-79).
///
/// Weights, the nutrition plan and the food diary are stored on the server under
/// the account, and (only when the matching flag is on) meal photos, label
/// photos and describe text are processed by Vertex AI. The notice says so once
/// and needs ONE tap to acknowledge. It must be acknowledged before the first
/// weight entry, plan save or diary write is sent and before the first
/// food-AI call; until then the write is DEFERRED, never lost. With the flags
/// off the notice still covers weights, plan and diary.
///
/// The answer is device-local (SharedPreferences, one key per account) and is
/// versioned: bumping [kDataNoticeVersion] changes the key, so the next write
/// asks again about the changed notice instead of inheriting an answer to a
/// different one. The key joins the account-deletion local wipe list in C25.
const int kDataNoticeVersion = 1;

/// Where the acknowledgement lives. An interface so tests (and the signed-out
/// session, which has no account to record it against) use the in-memory one.
abstract class DataNoticeStore {
  /// Whose answer this holds, or null when there is no account.
  String? get uid;

  Future<bool> isAcknowledged();

  /// Records the answer. Must leave [isAcknowledged] true for the rest of the
  /// session even if the durable write fails: a failed write costs one extra
  /// tap on the next launch, never a re-closed gate in the same breath.
  Future<void> acknowledge();
}

/// SharedPreferences-backed, one key per account and notice version.
class PrefsDataNoticeStore implements DataNoticeStore {
  PrefsDataNoticeStore({required this.uid, SharedPreferences? prefs})
      : _injected = prefs;

  @override
  final String uid;
  final SharedPreferences? _injected;

  bool _acknowledgedInSession = false;

  /// `data_notice.v1.<uid>`.
  String get key => dataNoticeKey(uid);

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  @override
  Future<bool> isAcknowledged() async {
    if (_acknowledgedInSession) return true;
    return (await _prefs).getBool(key) ?? false;
  }

  @override
  Future<void> acknowledge() async {
    _acknowledgedInSession = true;
    // `setBool` reports failure by RETURNING false; raise it so the caller
    // sees it (the session still proceeds, see the field above).
    final written = await (await _prefs).setBool(key, true);
    if (!written) {
      throw StateError('data notice: preferences refused to store $key');
    }
  }
}

/// The preference key for [uid] at the current [kDataNoticeVersion].
String dataNoticeKey(String uid, {int version = kDataNoticeVersion}) =>
    'data_notice.v$version.$uid';

/// Keeps the answer in memory only: the signed-out session and tests.
class InMemoryDataNoticeStore implements DataNoticeStore {
  InMemoryDataNoticeStore({bool acknowledged = false})
      : _acknowledged = acknowledged;

  bool _acknowledged;

  @override
  String? get uid => null;

  /// How many times [acknowledge] was called.
  int acknowledgeCalls = 0;

  @override
  Future<bool> isAcknowledged() async => _acknowledged;

  @override
  Future<void> acknowledge() async {
    _acknowledged = true;
    acknowledgeCalls++;
  }
}

/// The store for the signed-in account, or an in-memory one when there is none.
final dataNoticeStoreProvider = FutureProvider<DataNoticeStore>((ref) async {
  final uid = (await ref.watch(authUserProvider.future))?.uid;
  if (uid == null || uid.isEmpty) return InMemoryDataNoticeStore();
  return PrefsDataNoticeStore(uid: uid);
});

/// Whether the current notice version has been acknowledged. Loading or failed
/// reads count as NOT acknowledged (the write waits, nothing is lost).
/// Invalidate after the sheet records an answer.
final dataNoticeAcknowledgedProvider = FutureProvider<bool>((ref) async {
  final store = await ref.watch(dataNoticeStoreProvider.future);
  return store.isAcknowledged();
});

/// Returns true once the notice is acknowledged, showing the sheet first when it
/// is not. Returns false when the user dismisses the sheet or [context] is gone;
/// the caller then defers its write (it must not send it).
Future<bool> ensureDataNoticeAcknowledged(
  BuildContext context,
  WidgetRef ref,
) async {
  final store = await ref.read(dataNoticeStoreProvider.future);
  if (await store.isAcknowledged()) return true;
  if (!context.mounted) return false;
  final accepted = await showDataNoticeSheet(context);
  if (!accepted) return false;
  try {
    await store.acknowledge();
  } on StateError {
    // The durable write failed; the in-session answer stands (see the store).
  }
  ref.invalidate(dataNoticeAcknowledgedProvider);
  return true;
}

/// The one-tap sheet. Resolves true only on the explicit acknowledge button.
///
/// A framework modal route (focus moves into it, semantics outside are
/// blocked, focus returns to the trigger on close, D-85), a scrollable body so
/// 200 % text never clips, and the heading is a semantics header.
Future<bool> showDataNoticeSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DataNoticeSheet(),
  );
  return result ?? false;
}

class _DataNoticeSheet extends ConsumerWidget {
  const _DataNoticeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final flags = ref.watch(bodyScanFlagsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.dataNoticeTitle, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          Text(l10n.dataNoticeBody, style: theme.textTheme.bodyMedium),
          if (flags.foodAi) ...[
            const SizedBox(height: 12),
            Text(l10n.dataNoticeBodyFoodAi, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.dataNoticeAcknowledge),
            ),
          ),
        ],
      ),
    );
  }
}
