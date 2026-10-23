/// App wiring of the V0 offline command queue, used only when
/// `workoutCommandQueueEnabledProvider` is true (build define
/// `WORKOUT_COMMAND_QUEUE=true`). With the flag off nothing here is built.
///
/// Pieces: the per-uid runtime (SQLite store, acceptor, sender, retry timer),
/// the binding provider that opens and closes it with the signed-in account,
/// the writer proof and install id stores, the callable transport and the
/// gateway the set-completion path calls. Design and gaps:
/// `docs/v1/design/V0_APP_WIRING_2026-10-23.md`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/workout_queue_flag.dart';
import '../../../core/firebase/functions_region.dart';
import '../../auth/state/auth_providers.dart';
import 'canonical.dart';
import 'command_queue_store.dart';
import 'complete_set_acceptor.dart';
import 'providers.dart';
import 'sender.dart';
import 'status.dart';

/// Maps any raw id to an id that `isValidIdString` accepts (1..[max] chars of
/// [A-Za-z0-9_-], never of the reserved form `__...__`). A raw id that is
/// already valid is returned unchanged; otherwise the result is
/// `s_<sanitised prefix>_<16 hex of sha256(raw)>`, so distinct raw ids do not
/// collide and the mapping is deterministic.
String queueSafeId(String raw, {int max = 128}) {
  if (raw.length <= max && isValidIdString(raw)) return raw;
  final hash = crypto.sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
  final room = max - 2 - 1 - 16;
  var prefix = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  if (prefix.length > room) prefix = prefix.substring(0, room);
  return 's_${prefix}_$hash';
}
/// The queue session id of a UI session id (same value the chip reads).
String queueSessionIdOf(String uiSessionId) => queueSafeId(uiSessionId);

/// What the UI knows about one completed set. V0 mapping: one set per
/// exercise per session, so the logical set index is always 1.
class QueuedSet {
  const QueuedSet({
    required this.sessionId,
    required this.exerciseId,
    required this.dayId,
    required this.startedAtMs,
    required this.performedAtMs,
    this.weightKg,
    this.reps,
  });

  final String sessionId;
  final String exerciseId;
  final String? dayId;
  final int startedAtMs;
  final int performedAtMs;
  final double? weightKg;
  final int? reps;
}

/// Secret writer token per (uid, session), in secure storage. The first proof
/// the server sees for a session claims it (apply.ts step 6a), so a random
/// token created on first use needs no takeover step.
class WriterProofStore {
  WriterProofStore({FlutterSecureStorage? storage, Random? random})
      : _storage = storage ?? const FlutterSecureStorage(),
        _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;

  String _key(String uid, String sessionId) =>
      'workout_queue_writer_v1:${queueSafeId(uid, max: 64)}:$sessionId';

  /// Returns the stored proof or creates and stores one.
  Future<String?> proofFor(String uid, String sessionId) async {
    final key = _key(uid, sessionId);
    final existing = await _storage.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = base64Url
        .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    await _storage.write(key: key, value: fresh);
    return fresh;
  }
}

const String _kInstallIdKey = 'workout_queue_install_id_v1';

/// Random per-install id, persisted in shared preferences.
Future<String> loadOrCreateInstallId({SharedPreferences? prefs}) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  final existing = p.getString(_kInstallIdKey);
  if (existing != null && isValidIdString(existing)) return existing;
  final rng = Random.secure();
  final id = 'i${base64Url.encode(List<int>.generate(16, (_) => rng.nextInt(256))).replaceAll('=', '')}';
  await p.setString(_kInstallIdKey, id);
  return id;
}

/// Sends one command through the `submitWorkoutCommands` callable.
class CallableCommandTransport implements CommandTransport {
  CallableCommandTransport({FirebaseFunctions? functions})
      : _functions = functions ?? functionsForRegion;

  final FirebaseFunctions _functions;

  @override
  Future<TransportAnswer> send(CommandEnvelope envelope) async {
    final text = utf8.decode(envelope.payloadBytes);
    final sessionId = (jsonDecode(text) as Map)['sessionId'] as String;
    final res = await _functions.httpsCallable('submitWorkoutCommands').call(
      <String, Object?>{
        'sessionId': sessionId,
        'items': [
          {
            'payloadBytes': text,
            'payloadHash': envelope.payloadHash,
            'writerProof': envelope.writerProof,
            'writerEpochClaim': envelope.writerEpochClaim,
            'deviceInstallId': envelope.deviceInstallId,
            'clientBuild': envelope.clientBuild,
          }
        ],
      },
    );
    final data = res.data as Map;
    final results = data['results'] as List;
    if (results.isEmpty) throw StateError('empty results');
    final item = results.first as Map;
    final receipt = item['receipt'] as Map?;
    return TransportAnswer(
      code: item['code'] as String,
      revisionAfter: receipt?['revisionAfter'] as int?,
      serverTimeMs: (receipt?['serverTimeMs'] as num?)?.toInt(),
      retryAfterMs: (item['retryAfterMs'] as num?)?.toInt(),
    );
  }
}

/// Everything bound to one signed-in uid.
class WorkoutQueueRuntime {
  WorkoutQueueRuntime({
    required this.uid,
    required this.store,
    required this.acceptor,
    required this.sender,
    this.pollInterval = const Duration(seconds: 15),
  });

  final String uid;
  final CommandQueueStore store;
  final CompleteSetAcceptor acceptor;
  final CommandSender sender;
  final Duration pollInterval;

  Timer? _timer;
  bool _disposed = false;

  /// Starts the periodic retry. The sender keeps per-session backoff holds, so
  /// a short period only probes; it does not hammer the server.
  void start() {
    _timer ??= Timer.periodic(pollInterval, (_) => kick());
    kick();
  }

  /// Sends what is eligible; never throws.
  void kick() {
    if (_disposed) return;
    unawaited(sender.sendAvailable().catchError((Object e) {
      debugPrint('workout queue send failed: ${e.runtimeType}');
      return <SendReport>[];
    }));
  }

  /// Stops the timer and closes the store. Deletes nothing.
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await store.dispose();
  }
}

Future<WorkoutQueueRuntime> openWorkoutQueueRuntime(String uid) async {
  final store = await openOfflineCommandQueueStore(uid);
  final installId = await loadOrCreateInstallId();
  final proofs = WriterProofStore();
  return WorkoutQueueRuntime(
    uid: uid,
    store: store,
    acceptor: CompleteSetAcceptor(store: store, originDeviceInstallId: installId),
    sender: CommandSender(
      store: store,
      transport: CallableCommandTransport(),
      deviceInstallId: installId,
      clientBuild:
          const String.fromEnvironment('APP_VERSION', defaultValue: 'dev'),
      writerProof: proofs.proofFor,
    ),
  );
}

/// The runtime of the signed-in uid, as a future (null: signed out or the
/// flag is off). Written only by [workoutQueueBindingProvider].
final workoutQueueRuntimeFutureProvider =
    StateProvider<Future<WorkoutQueueRuntime>?>((ref) => null);

/// Opens the queue for the signed-in account and closes it on sign-out or
/// account change. Watched from the app root; a no-op with the flag off.
final workoutQueueBindingProvider = Provider<void>((ref) {
  if (!ref.watch(workoutCommandQueueEnabledProvider)) return;
  String? boundUid;
  Future<WorkoutQueueRuntime>? current;

  Future<void> close() async {
    final f = current;
    current = null;
    boundUid = null;
    // Deferred: this may run while the binding provider is being built.
    Future.microtask(() {
      try {
        if (current == null) {
          ref.read(workoutQueueRuntimeFutureProvider.notifier).state = null;
        }
      } catch (_) {
        // The container is already disposed.
      }
    });
    if (f == null) return;
    try {
      await (await f).dispose();
    } catch (e) {
      debugPrint('workout queue close failed: ${e.runtimeType}');
    }
  }

  ref.listen<AsyncValue<dynamic>>(authUserProvider, (previous, next) {
    if (!next.hasValue) return;
    final uid = (next.value as dynamic)?.uid as String?;
    if (uid == boundUid) return;
    // Close the old scope first (its store holds the database open), then open.
    final closing = close();
    if (uid == null || uid.isEmpty) return;
    boundUid = uid;
    final opened = closing.then((_) => openWorkoutQueueRuntime(uid));
    current = opened;
    opened.then((r) => r.start(), onError: (Object e) {
      debugPrint('workout queue open failed: ${e.runtimeType}');
    });
    Future.microtask(() {
      if (current == opened) {
        ref.read(workoutQueueRuntimeFutureProvider.notifier).state = opened;
      }
    });
  }, fireImmediately: true);
  ref.onDispose(() => unawaited(close()));
});

/// Used by the set-completion path (flag on only).
class WorkoutQueueGateway {
  WorkoutQueueGateway(this._ref);

  final Ref _ref;

  /// Durably commits the set locally. Throws when it was not saved (no
  /// account, queue not open, store error, cap reached): the caller must then
  /// show an error and must not start the rest timer.
  Future<void> acceptSet(QueuedSet set) async {
    final f = _ref.read(workoutQueueRuntimeFutureProvider);
    if (f == null) throw StateError('Workout queue is not available');
    final rt = await f.timeout(const Duration(seconds: 5));
    final sessionId = queueSessionIdOf(set.sessionId);
    final exerciseId = queueSafeId(set.exerciseId);
    final dayId = set.dayId == null ? null : queueSafeId(set.dayId!);
    final reps = set.reps;
    final grams = set.weightKg == null ? null : (set.weightKg! * 1000).round();
    await rt.acceptor.accept(CompleteSetIntent(
      sessionId: sessionId,
      exerciseId: exerciseId,
      setIndex: 1,
      intentKey: 'markComplete:$sessionId:$exerciseId:1',
      body: <String, Object?>{
        'mode': 'APPEND',
        'setId': displaySetId(1),
        'performedConfirmed': true,
        'actualReps': reps,
        'actualRepsConfirmed': reps != null,
        'targetReps': null,
        'loadGrams': grams,
        'source': 'app',
        'performedAtClientMs': set.performedAtMs,
      },
      sessionInit: <String, Object?>{
        'titleKey': dayId == null ? 'default' : 'day:${queueSafeId(set.dayId!, max: 64)}',
        'dayId': dayId,
        'startedAtClientMs': set.startedAtMs,
      },
    ));
    rt.kick();
  }
}

final workoutQueueGatewayProvider =
    Provider<WorkoutQueueGateway>((ref) => WorkoutQueueGateway(ref));

/// Sync counts of one queue session for the chip (flag on only; the chip is
/// not built with the flag off). Null until the queue is open.
final workoutQueueSessionStatusProvider =
    StreamProvider.family<SessionSyncStatus?, String>((ref, uiSessionId) async* {
  final f = ref.watch(workoutQueueRuntimeFutureProvider);
  if (f == null) {
    yield null;
    return;
  }
  final WorkoutQueueRuntime rt;
  try {
    rt = await f;
  } catch (_) {
    yield null;
    return;
  }
  final id = queueSessionIdOf(uiSessionId);
  yield* StoreSyncStatusSource(rt.store)
      .watch()
      .map((snap) => snap.forSession(id));
});

