import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;

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

/// [MachineDescriber] over Gemini, through the same Firebase AI wiring and the
/// same resize the classifier uses.
class GeminiMachineDescriber implements MachineDescriber {
  GeminiMachineDescriber({
    CloudAsk? ask,
    PhotoBytes? photoBytes,
    this.modelName = kVisionModel,
    this.timeout = const Duration(seconds: 20),
  })  : _ask = ask,
        _photoBytes = photoBytes ?? _resize;

  final String modelName;

  /// Same deadline as recognition. This is the user's second wait on one
  /// photo, so a stalled request must give up rather than spin — the failure
  /// the operator reported ("долго ждёт и ничего") was exactly a call with no
  /// deadline at all.
  final Duration timeout;

  final CloudAsk? _ask;
  final PhotoBytes _photoBytes;

  late final CloudAsk _cloud = _ask ?? firebaseCloudAsk(modelName: modelName);

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
      final bytes = await _photoBytes(path);
      text = await _cloud(bytes, buildPrompt(languageCode)).timeout(timeout);
    } catch (e) {
      debugPrint('could not describe the unknown machine: $e');
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

  /// The question. Note what it does NOT do: it offers no list to choose from.
  /// The classifier's list exists so the model cannot invent a machine we have
  /// no page for; here there is no page by definition, and constraining the
  /// answer to our vocabulary would produce the wrong name for the thing the
  /// user is standing in front of.
  @visibleForTesting
  static String buildPrompt(String languageCode) {
    // Same mapping the AI exercise generator uses
    // (features/ai_coach/ai_exercise_generator.dart) so both cloud answers
    // land in one language rather than two.
    final language = languageCode == 'ru' ? 'Russian' : 'English';
    return '''
A gym app user photographed a piece of equipment the app has no page for. Look
ONLY at the machine closest to the centre of the photo; ignore what is at the
edges.

Answer with JSON only:
{"isGymEquipment": true or false,
 "name": "<short everyday name of this machine>",
 "summary": "<1-2 sentences: what it is and what it trains>",
 "uses": ["<one short exercise done on it>", "..."]}

Rules:
- Write "name", "summary" and every line of "uses" in $language.
- If the photo is not gym equipment at all — a person, a pet, a room, a meal —
  answer {"isGymEquipment": false} and nothing else. Do not describe it.
- Name the machine by what it is, not by a brand you think you recognise.
- 3 to 5 lines in "uses", each a real exercise performed on THIS machine, at
  most about six words.
- No markdown, no commentary.''';
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
    } catch (e) {
      debugPrint('machine description was not JSON: $e');
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
