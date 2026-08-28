import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;

import '../../../core/firebase/functions_region.dart';
import 'gemini_equipment_service.dart';
import 'machine_card.dart';

/// The second question, asked only when the first one came back empty.
///
/// The recogniser answers with machines the app has a page for, and it is
/// deliberately allowed to say `unknown` rather than pick the nearest thing it
/// recognises. That leaves a real gap: the user aimed at a real machine and got
/// nothing. Operator: *"если есть в каталоге то показывать из каталога сразу, а
/// если нет — объяснить человеку, что за железка перед ним и что на нем можно
/// делать и сохранить карточку тренажера"*.
///
/// So this asks the model a different question about the same photo — not
/// "which of ours is it" but "what is this and what is it for" — and turns the
/// answer into a [MachineCard]: something to read now, and a record of what to
/// film later.
abstract class MachineDescriber {
  /// Describes the machine in [path], or returns null when there is nothing
  /// honest to say about it.
  ///
  /// Never throws. This runs after the user has already been told the machine
  /// is not in the catalog; failing the whole scan a second time helps nobody.
  Future<MachineCard?> describe({
    required String path,
    String languageCode = 'ru',
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  });
}

/// Loads a photo as the bytes to upload. Injectable so tests never need a file.
typedef PhotoBytes = Future<Uint8List> Function(String path);

/// Signature of "send an already-resized photo plus a language code to the
/// machine describer, get its raw JSON text back" — injectable for tests, so
/// the suite never needs a real `FirebaseFunctions`.
///
/// Two args, not the old [CloudAsk]'s (bytes, full prompt): unlike before G1's
/// migration of this class, there is no client-built prompt to pass any more
/// — the `aiMachineDescription` Cloud Function builds the whole prompt
/// server-side (`functions/src/ai_machine_description.ts`) from a fixed
/// template plus the language code, which it also validates against an
/// explicit ru/en allowlist rather than trusting it as free text.
typedef CloudDescriptionAsk = Future<String?> Function(
    Uint8List imageBytes, String languageCode);

/// The Cloud Function name this surface calls. Named once so
/// [cloudFunctionsMachineDescriptionAsk] and its test cannot drift apart on a
/// typo.
const String kMachineDescriptionFunctionName = 'aiMachineDescription';

/// Builds the request body sent to [kMachineDescriptionFunctionName].
///
/// Pulled out of [cloudFunctionsMachineDescriptionAsk] and independently
/// unit-tested, mirroring [buildEquipmentRecognitionRequest]'s own precedent
/// in `gemini_equipment_service.dart`: `FirebaseFunctions`/`HttpsCallable`
/// have private constructors, so this is what makes the request shape
/// testable without the SDK.
@visibleForTesting
Map<String, dynamic> buildMachineDescriptionRequest(
        Uint8List imageBytes, String languageCode) =>
    {
      'mimeType': 'image/jpeg',
      'imageBase64': base64Encode(imageBytes),
      'languageCode': languageCode,
    };

/// Extracts the answer text from [kMachineDescriptionFunctionName]'s reply.
/// The other half of the same testable-without-the-SDK split as
/// [buildMachineDescriptionRequest].
@visibleForTesting
String? extractMachineDescriptionText(Map<String, dynamic> data) =>
    data['text'] as String?;

/// The default [CloudDescriptionAsk]: routes through the
/// `aiMachineDescription` Cloud Function rather than calling
/// `FirebaseAI.googleAI()` directly.
///
/// G1: the third of the four mobile call sites migrated off a direct
/// client-side Gemini call (see `gemini_equipment_service.dart` for the
/// second). The photo is already resized to a small JPEG by
/// `resizeForCloud` before this runs.
CloudDescriptionAsk cloudFunctionsMachineDescriptionAsk(
    {FirebaseFunctions? functions}) {
  final fns = functions ?? functionsForRegion;
  return (Uint8List bytes, String languageCode) async {
    final result = await fns
        .httpsCallable(kMachineDescriptionFunctionName)
        .call<Map<String, dynamic>>(
            buildMachineDescriptionRequest(bytes, languageCode));
    return extractMachineDescriptionText(result.data);
  };
}

/// [MachineDescriber] over Gemini, through the `aiMachineDescription` Cloud
/// Function and the same resize the classifier uses.
class GeminiMachineDescriber implements MachineDescriber {
  GeminiMachineDescriber({
    CloudDescriptionAsk? ask,
    PhotoBytes? photoBytes,
    FirebaseFunctions? functions,
    this.timeout = const Duration(seconds: 30),
  })  : _ask = ask,
        _injected = functions,
        _photoBytes = photoBytes ?? _resize;

  /// 30s, not 20s: mirrors `GeminiVisualEquipmentService.timeout`'s own fix
  /// (`gemini_equipment_service.dart`) for the identical client/server
  /// timeout-race GPT-PM's G1 review caught on that slice first. G1's
  /// `aiMachineDescription` Cloud Function bounds the MODEL call itself at
  /// 20s (`functions/src/ai_machine_description.ts`), but that budget only
  /// starts after auth, request validation, and the quota-ledger transaction
  /// have already run server-side — none of which this client-side clock
  /// accounts for. 30s gives real margin over the server's own 20s model
  /// budget rather than racing it.
  ///
  /// This is the SERVICE-level deadline, and it covers the WHOLE operation —
  /// resize (`_photoBytes`) AND the network call — not just the network leg.
  /// GPT-PM's G1 round-1 review of this class caught an earlier version that
  /// applied this timeout to the cloud call alone, leaving `_photoBytes`
  /// unbounded from this class's own perspective: a slow resize plus a
  /// legitimate near-30s network round trip could together exceed the
  /// controller's outer budget even though the network leg's OWN sub-timer
  /// had not fired, discarding a paid, quota-charged answer for no real
  /// reason — the exact race this whole timeout hierarchy exists to close,
  /// one layer further out than where it was first found. Wrapping the
  /// entire operation here is what makes the documented invariant
  /// (server 20s < this 30s < the controller's still-larger budget) actually
  /// hold, rather than merely describe an ordering of numbers that isn't
  /// structurally enforced.
  ///
  /// One layer further out still: `visual_equipment_providers.dart`'s
  /// `_describeInstead` wraps the whole `describe()` call (this timeout
  /// included) in a further outer `.timeout()` of its own — see
  /// `describeTimeoutProvider` there for why a THIRD, still-larger number
  /// exists above this one, and why reusing the classifier's
  /// `recogniseTimeoutProvider` for both would have silently defeated this
  /// fix.
  final Duration timeout;

  final CloudDescriptionAsk? _ask;
  final FirebaseFunctions? _injected;
  final PhotoBytes _photoBytes;

  late final CloudDescriptionAsk _cloud =
      _ask ?? cloudFunctionsMachineDescriptionAsk(functions: _injected);

  static Future<Uint8List> _resize(String path) =>
      compute(resizeForCloud, path);

  @override
  Future<MachineCard?> describe({
    required String path,
    String languageCode = 'ru',
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  }) async {
    final String? text;
    try {
      // Sequenced, not one composite `.timeout()` over both stages — GPT-PM's
      // G1 round-2 review caught why that shape was still wrong even though it
      // fixed round-1's "resize is unbounded" gap: `Future.timeout()` does NOT
      // cancel the source future, it only stops waiting on it — the original
      // computation keeps running to completion in the background regardless.
      // With one composite future, a resize alone overrunning [timeout] would
      // still let `_cloud` start (and spend real quota/provider cost) once
      // resize finally finished, for an answer this method had already given
      // up on and returned null for. Timing resize on its own first — and only
      // starting the network call at all if resize left real budget — means
      // the network call is simply never initiated once the deadline is
      // already spent, rather than started and then abandoned.
      // `Stopwatch`, not `DateTime.now()` subtraction — GPT-PM's G1 round-3
      // review caught that wall-clock time is not monotonic (NTP sync, DST,
      // a user changing the device clock), so a `DateTime`-based elapsed
      // measurement could over- or under-state the real remaining budget.
      // `Stopwatch` measures real elapsed time regardless of wall-clock
      // adjustments.
      final stopwatch = Stopwatch()..start();
      final bytes = await _photoBytes(path).timeout(timeout);
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('resize left no budget for the network call');
      }
      text = await _cloud(bytes, languageCode).timeout(remaining);
    } catch (e, stackTrace) {
      debugPrint('could not describe the unknown machine: $e');
      // Fire-and-forget, sanitized (error + stack trace only, no photo
      // bytes/prompt/health content) -- same OBS-1 telemetry contract as
      // gemini_equipment_service.dart's own catch block; must never delay or
      // alter the null this method already returns on failure.
      try {
        unawaited(
          FirebaseCrashlytics.instance.recordError(
            e,
            stackTrace,
            fatal: false,
            reason: 'cloud machine description failed',
          ),
        );
      } catch (_) {
        // Reporting failure is not itself reportable.
      }
      return null;
    }
    if (text == null || text.trim().isEmpty) return null;
    return parseDescription(
      text,
      photoPath: path,
      recognisedAs: recognisedAs,
      confidence: confidence,
      now: now,
    );
  }

  /// Turns the model's JSON into a card, or into nothing.
  ///
  /// A card is shown to the user as the app's answer, so half an answer is
  /// worse than none: an entry with no name, or no explanation of what the
  /// machine is, would appear in "my machines" as a blank row promising content
  /// that nobody could ever film, because nobody would know what it was.
  @visibleForTesting
  static MachineCard? parseDescription(
    String text, {
    required String photoPath,
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  }) {
    final cleaned = text
        .replaceAll(RegExp(r'^\s*```(?:json)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (e, stackTrace) {
      debugPrint('machine description was not JSON: $e');
      // A malformed response is a real signal (prompt/schema drift), not an
      // expected condition -- same sanitized fire-and-forget contract as the
      // network catch above; never the raw model text (may echo user photo
      // description), only the parse exception and stack trace.
      try {
        unawaited(
          FirebaseCrashlytics.instance.recordError(
            e,
            stackTrace,
            fatal: false,
            reason: 'machine description response was not valid JSON',
          ),
        );
      } catch (_) {
        // Reporting failure is not itself reportable.
      }
      return null;
    }
    if (decoded is! Map) return null;

    // The model was given an explicit way to say "that is not a machine", and
    // it must be believed. Without this the answer to a photo of a dog is a
    // confident description of a rowing machine.
    if (decoded['isGymEquipment'] == false) return null;

    final name = (decoded['name'] as String? ?? '').trim();
    final summary = (decoded['summary'] as String? ?? '').trim();
    if (name.isEmpty || summary.isEmpty) {
      debugPrint('machine description had no name or no summary; dropped');
      return null;
    }

    final uses = <String>[];
    final rawUses = decoded['uses'];
    if (rawUses is List) {
      for (final u in rawUses) {
        if (u is! String) continue;
        final line = u.trim();
        // Six-word lines were asked for; a paragraph here is the model
        // ignoring the shape, and it would run off a list tile.
        if (line.isEmpty || line.length > 120) continue;
        if (!uses.contains(line)) uses.add(line);
        if (uses.length == 5) break;
      }
    }

    final at = now ?? DateTime.now();
    return MachineCard(
      id: machineCardId(name),
      name: name,
      summary: summary,
      uses: uses,
      firstSeenAt: at,
      lastSeenAt: at,
      // The user's own photo. It is the only evidence of what they actually
      // pointed at, and filming the missing clip starts from the real machine
      // rather than from a name.
      photoPath: photoPath,
      recognisedAs: recognisedAs,
      confidence: confidence,
    );
  }
}

/// Deterministic [MachineDescriber] for tests and for the default binding.
class MockMachineDescriber implements MachineDescriber {
  MockMachineDescriber({this.card});

  /// Null means "the model had nothing to say", which is a real outcome and
  /// the one the UI must survive.
  final MachineCard? card;

  @override
  Future<MachineCard?> describe({
    required String path,
    String languageCode = 'ru',
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  }) async =>
      card;
}
