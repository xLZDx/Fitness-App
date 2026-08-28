import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../../core/debug/g3_step10b_probe.dart';
import '../../../core/firebase/functions_region.dart';
import '../../equipment/data/equipment_alias_index.dart';
import 'visual_equipment_match.dart';
import 'visual_equipment_service.dart';

/// Signature of "send an already-resized photo to the equipment recognizer,
/// get its raw JSON text back" — injectable for tests, so the suite never
/// needs a real `FirebaseFunctions`.
///
/// One arg, not two: there is no client-built prompt to pass any more — G1's
/// `aiEquipmentRecognition` Cloud Function builds the whole prompt server-side
/// (`functions/src/ai_equipment_recognition.ts`, which carries its own copy
/// of the canonical machine list this file used to export as
/// `kCanonicalMachines`/`buildPrompt()` — both deleted here since they no
/// longer drive anything a real call sends). `machine_describer.dart`'s
/// `CloudDescriptionAsk` is the same shape one file over, migrated the same
/// way once `GeminiMachineDescriber` moved server-side too — this file no
/// longer has any direct-Gemini call site of its own (the old two-arg
/// `CloudAsk`/`firebaseCloudAsk()` this typedef used to sit beside are gone,
/// dead once `GeminiMachineDescriber` stopped being their only caller).
typedef CloudRecognitionAsk = Future<String?> Function(Uint8List imageBytes);

/// The Cloud Function name this surface calls. Named once so
/// [cloudFunctionsEquipmentAsk] and its test cannot drift apart on a typo.
const String kEquipmentRecognitionFunctionName = 'aiEquipmentRecognition';

/// Builds the request body sent to [kEquipmentRecognitionFunctionName].
///
/// Pulled out of [cloudFunctionsEquipmentAsk] and independently unit-tested:
/// `FirebaseFunctions`/`HttpsCallable` have private constructors (verified
/// against `cloud_functions`' own source), so unlike most other injectable
/// seams in this codebase they cannot be faked in a plain unit test without
/// heavier Firebase test scaffolding this project does not have. GPT-PM's G1
/// round-1 review named the resulting gap directly: every existing test for
/// this class injects `ask` and never exercises this function's real request/
/// response shape, so a typo in the function name or either JSON key here
/// would compile, ship, and only fail in production. Splitting the shape
/// into its own pure function is what makes it testable without the SDK.
@visibleForTesting
Map<String, dynamic> buildEquipmentRecognitionRequest(Uint8List imageBytes) => {
      'mimeType': 'image/jpeg',
      'imageBase64': base64Encode(imageBytes),
    };

/// Extracts the answer text from [kEquipmentRecognitionFunctionName]'s reply.
/// The other half of the same testable-without-the-SDK split as
/// [buildEquipmentRecognitionRequest].
@visibleForTesting
String? extractEquipmentRecognitionText(Map<String, dynamic> data) => data['text'] as String?;

/// The default [CloudRecognitionAsk]: routes through the `aiEquipmentRecognition`
/// Cloud Function rather than calling `FirebaseAI.googleAI()` directly.
///
/// G1: this is the second of the four mobile call sites migrated off a direct
/// client-side Gemini call (see `ai_coach_service.dart` for the first). The
/// photo is already resized to a small JPEG by [resizeForCloud] before this
/// runs, so base64-encoding it here does not undo that saving.
CloudRecognitionAsk cloudFunctionsEquipmentAsk({FirebaseFunctions? functions}) {
  final fns = functions ?? functionsForRegion;
  return (Uint8List bytes) async {
    final result = await fns
        .httpsCallable(kEquipmentRecognitionFunctionName)
        .call<Map<String, dynamic>>(buildEquipmentRecognitionRequest(bytes));
    return extractEquipmentRecognitionText(result.data);
  };
}

/// Cloud recogniser: Gemini through the `aiEquipmentRecognition` Cloud Function.
///
/// Why this exists: the on-device model is 10 catalogue-trained classes and
/// on a real gym floor it misfired badly enough to call two flat benches a
/// treadmill. Gemini sees the actual machine. G1 moved the model call itself
/// server-side; the reply is still resolved through [EquipmentAliasIndex]
/// entirely client-side (that logic never touched the network), so the model
/// cannot invent a machine we have no page for: an unresolvable answer
/// degrades to "no match", never to a guess.
class GeminiVisualEquipmentService implements VisualEquipmentService {
  GeminiVisualEquipmentService({
    Future<EquipmentAliasIndex>? index,
    CloudRecognitionAsk? ask,
    FirebaseFunctions? functions,
    this.timeout = const Duration(seconds: 30),
  })  : _index = index ?? EquipmentAliasIndex.load(),
        _ask = ask,
        _injected = functions;

  final Future<EquipmentAliasIndex> _index;
  final CloudRecognitionAsk? _ask;
  final FirebaseFunctions? _injected;

  /// Verified live 2026-07-30: with the model's default "thinking" a single
  /// photo took 25-31s; with thinking disabled, 2-5s typically (occasional
  /// preview-model queueing still hit 15-18s). The operator's report — long
  /// waits, then nothing after several tries — is this combined with a
  /// classifyFile call that had NO deadline: a genuinely stalled request just
  /// spun the spinner forever and never reached the on-device fallback below.
  ///
  /// 30s, not 20s: G1's `aiEquipmentRecognition` Cloud Function bounds the
  /// MODEL call itself at 20s (`functions/src/ai_equipment_recognition.ts`),
  /// but that budget only starts after auth, request validation and the
  /// quota-ledger transaction have already run server-side — none of which
  /// this client-side clock accounts for. GPT-PM's G1 round-1 review of this
  /// migration caught the two clocks matching exactly: a cold Functions
  /// instance plus that overhead could legitimately take the total past 20s
  /// while the model call itself is still on track to succeed, and this
  /// timer firing first would discard a paid, quota-charged answer and fall
  /// back to the much weaker on-device recognizer for no real reason. 30s
  /// gives real margin over the server's own 20s model budget rather than
  /// racing it — shrinking the server's budget instead was rejected because
  /// it was already tuned against measured real latency (see above), and
  /// cutting it would turn some of those legitimate 15-18s answers into
  /// timeouts instead.
  final Duration timeout;

  /// Bounded performance signal (GPT-PM round-2, Sec 6.5): the failures path
  /// above is only half of what OBS-1 asked for. 20s, not something tighter,
  /// because it is the point this file already treats as meaningful --
  /// [timeout]'s own comment anchors it as the server's real model budget, so
  /// a successful call that still took that long is a genuine performance
  /// signal, not routine cold-start/queueing noise (measured 15-18s cases
  /// documented above).
  ///
  /// Public (not `_`-prefixed) so `visual_equipment_providers.dart`'s
  /// `recogniseTimeoutProvider` -- which wraps this ENTIRE service's
  /// `classifyFile()` call, starting before this stopwatch does -- can be
  /// tested against it directly. The two were found live, on a real device,
  /// numerically equal (MVP1.G3 Step 10B, `core/DECISION_LOG.md`): the outer
  /// clamp always fired first, so a successful-but-slow answer was shown to
  /// the user as a timeout every time, never as the success it was.
  static const Duration kSlowInferenceThreshold = Duration(seconds: 20);

  late final CloudRecognitionAsk _cloud =
      _ask ?? cloudFunctionsEquipmentAsk(functions: _injected);

  Future<String?> _askCloud(Uint8List bytes) => _cloud(bytes).timeout(timeout);

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    final index = await _index;
    // Resized off the UI isolate: a camera still can run several MB, and on
    // gym wifi/LTE the upload itself was a real chunk of the reported delay.
    // 1024px keeps the model's answer quality (verified live) while cutting
    // the payload roughly 3-4x versus a full-resolution JPEG.
    final bytes = await compute(resizeForCloud, path);
    final String? text;
    final stopwatch = Stopwatch()..start();
    try {
      // MVP1.G3 Step 10B fault injection -- see g3_step10b_probe.dart. Dead
      // code (compiler-eliminated) in every build that does not pass
      // --dart-define=G3_STEP10B_PROBE=true --dart-define=G3_STEP10B_INFERENCE_FAIL=true.
      if (G3Step10bProbe.forceInferenceFailure) {
        throw const VisualEquipmentException(
            'G3_STEP10B_PROBE: injected cloud recognition failure');
      }
      if (G3Step10bProbe.injectedInferenceDelaySeconds > 0) {
        // Fault injection continued: intercepts AT the `_askCloud()`
        // dependency boundary rather than padding a real call, because the
        // real `aiEquipmentRecognition` Cloud Function is not deployed in
        // this environment -- it is one of the AI Gateway callables Step 10A
        // deliberately left held back for a future gate, and this step must
        // not touch that boundary just to manufacture evidence. The delay
        // below stands in for real network/Gemini latency (not claimed as
        // real -- see the labelled evidence this produces); everything AFTER
        // it -- the stopwatch/threshold check, JSON parsing, alias
        // resolution, and what the screen shows -- is the real, unmodified
        // production path running on a well-formed canned success.
        await Future<void>.delayed(
          Duration(seconds: G3Step10bProbe.injectedInferenceDelaySeconds),
        );
        text = '{"machine": "treadmill", "confidence": 0.91}';
      } else {
        text = await _askCloud(bytes);
      }
    } catch (e, stackTrace) {
      // Error + stack trace only -- no photo bytes, no prompt text, no
      // health/profile content reaches Crashlytics. Fire-and-forget: this
      // must never delay or alter the exception thrown to the caller below.
      // Same guard as main.dart's Crashlytics calls: telemetry must never
      // break the feature it instruments (and has no app to report against
      // at all in a plain `flutter test` run).
      try {
        // Branch at the call site, not inside the probe: G3_STEP10B_PROBE=false
        // (every normal build) must call FirebaseCrashlytics directly, with
        // NO g3_step10b_probe.dart frame in between. A null-stack report like
        // the slow-inference one below is attributed to whatever Dart frame
        // last called the plugin synchronously -- routing every build through
        // a wrapper function moved that frame into the test harness and
        // mis-grouped real production events under it. Found live during
        // MVP1.G3 Step 10B's own GPT-PM review (`core/DECISION_LOG.md`).
        if (G3Step10bProbe.kEnabled) {
          unawaited(
            G3Step10bProbe.recordError(
              e,
              stackTrace,
              fatal: false,
              reason: 'cloud equipment recognition failed',
            ),
          );
        } else {
          unawaited(
            FirebaseCrashlytics.instance.recordError(
              e,
              stackTrace,
              fatal: false,
              reason: 'cloud equipment recognition failed',
            ),
          );
        }
      } catch (_) {
        // Reporting failure is not itself reportable -- see above.
      }
      throw VisualEquipmentException('cloud recognition failed: $e');
    }
    stopwatch.stop();
    // Disjoint from the failure report above on purpose: a call that timed
    // out already went through the catch block, so this only fires for a
    // call that SUCCEEDED but was still unusually slow -- the performance
    // half of OBS-1, not a second copy of the failure half.
    if (stopwatch.elapsed >= kSlowInferenceThreshold) {
      final message = 'equipment recognition succeeded but took '
          '${stopwatch.elapsedMilliseconds}ms '
          '(>= ${kSlowInferenceThreshold.inSeconds}s threshold)';
      try {
        // Same call-site branch as the catch block above -- see that comment.
        if (G3Step10bProbe.kEnabled) {
          unawaited(
            G3Step10bProbe.recordError(
              message,
              null,
              fatal: false,
              reason: 'slow equipment recognition inference',
            ),
          );
        } else {
          unawaited(
            FirebaseCrashlytics.instance.recordError(
              message,
              null,
              fatal: false,
              reason: 'slow equipment recognition inference',
            ),
          );
        }
      } catch (_) {
        // Reporting failure is not itself reportable -- see above.
      }
    }
    if (text == null || text.trim().isEmpty) {
      throw VisualEquipmentException('cloud recognition returned no answer');
    }
    return parseResponse(text, index, topK: topK);
  }

  /// Parses the model's JSON (tolerating ```json fences) and resolves every
  /// named machine through the alias index. Unresolvable names are dropped
  /// with a log — never guessed at.
  @visibleForTesting
  static List<VisualMatch> parseResponse(
    String text,
    EquipmentAliasIndex index, {
    int topK = 3,
  }) {
    final cleaned = text
        .replaceAll(RegExp(r'^\s*```(?:json)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (e) {
      throw VisualEquipmentException('cloud answer was not JSON: $e');
    }
    if (decoded is! Map) {
      throw VisualEquipmentException('cloud answer had no object');
    }

    final raw = <VisualMatch>[];
    void addCandidate(Object? name, Object? confidence) {
      if (name is! String) return;
      if (name.trim().toLowerCase() == 'unknown') return;
      final id = index.resolve(name);
      if (id == null) {
        debugPrint('cloud named "$name" but the registry has no such machine');
        return;
      }
      final c = confidence is num ? confidence.toDouble().clamp(0.0, 1.0) : 0.5;
      raw.add(VisualMatch(equipmentId: id, confidence: c, labelHint: name));
    }

    addCandidate(decoded['machine'], decoded['confidence']);
    final alts = decoded['alternatives'];
    if (alts is List) {
      for (final a in alts) {
        if (a is Map) addCandidate(a['machine'], a['confidence']);
      }
    }

    // One machine may arrive twice (main + alternative); keep the best.
    final best = <String, VisualMatch>{};
    for (final m in raw) {
      final prev = best[m.equipmentId];
      if (prev == null || m.confidence > prev.confidence) {
        best[m.equipmentId] = m;
      }
    }
    return rankTopK(best.values, minConfidence: 0.01, limit: topK);
  }
}

/// Runs on a background isolate via [compute]: decodes the photo, downsizes
/// to at most 1024px on the long edge, and re-encodes as JPEG. A resize
/// failure (corrupt file, unsupported format) falls back to the original
/// bytes rather than throwing — a slightly larger upload beats no upload.
///
/// Shared with the machine describer: when a photo is not in the catalog it is
/// sent twice, and the second question must not re-do the resize differently.
Uint8List resizeForCloud(String path) {
  final bytes = File(path).readAsBytesSync();
  try {
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    decoded = img.bakeOrientation(decoded);
    if (decoded.width <= 1024 && decoded.height <= 1024) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
    }
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: 1024)
        : img.copyResize(decoded, height: 1024);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
  } catch (e) {
    debugPrint('cloud photo resize failed, sending original: $e');
    return bytes;
  }
}

/// Cloud first, on-device fallback.
///
/// The cloud path needs network + the Firebase AI API enabled; the on-device
/// model needs neither. Any cloud failure falls back silently-but-logged, so
/// the user in a basement gym still gets an answer — the weaker one, honestly
/// scored. Only when BOTH fail does the user see an error.
class HybridVisualEquipmentService
    implements VisualEquipmentService, FallbackReportingRecogniser {
  HybridVisualEquipmentService({required this.cloud, required this.local});

  final VisualEquipmentService cloud;
  final VisualEquipmentService local;

  bool _lastAnsweredOffline = false;

  /// R2.2 state 12. The fallback used to be invisible: "silently-but-logged"
  /// meant the user got the weaker answer, honestly scored, but was never told
  /// it came from the weaker model — so a low-confidence result in a basement
  /// gym looked like the app being bad at its job rather than the network
  /// being absent.
  @override
  bool get lastAnsweredOffline => _lastAnsweredOffline;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    Object? cloudError;
    try {
      final answer = await cloud.classifyFile(path: path, topK: topK);
      _lastAnsweredOffline = false;
      return answer;
    } catch (e) {
      cloudError = e;
      debugPrint('cloud recognition unavailable, falling back on-device: $e');
    }
    try {
      final answer = await local.classifyFile(path: path, topK: topK);
      _lastAnsweredOffline = true;
      return answer;
    } catch (e) {
      // Both failed: there is no answer, so there is nothing to label as
      // having come from the fallback.
      _lastAnsweredOffline = false;
      throw VisualEquipmentException(
          'recognition failed (cloud: $cloudError; on-device: $e)');
    }
  }
}
