import 'package:flutter/foundation.dart';

/// A machine the app photographed, recognised as real, and has nothing for.
///
/// ## Why this exists
///
/// The scanner's job is not to find the nearest match in our catalog. Operator:
/// *"смысл скана тренажера не в том чтобы найти подходящий из каталога, а
/// показать людям что это за тренажер и что на нем можно делать"*. When the
/// machine IS in the catalog the app shows the catalog immediately; when it is
/// not, it still owes the user an answer, and it owes us a record.
///
/// So an unrecognised machine produces a card rather than a shrug. The card
/// carries what the model could tell about the thing in front of the user, and
/// the user sees it — marked as content being prepared, not hidden. Operator,
/// asked directly whether the card should be visible: *"пользователю тоже видна
/// как «контент готовится»"*.
///
/// ## Why the photo is kept
///
/// It is the only evidence of what the user actually pointed at. A name alone
/// cannot tell us whether the model got it right, and the whole point of
/// recording these is to add the missing clip and details later — which needs
/// to start from the real machine, not from a guess about it.
@immutable
class MachineCard {
  const MachineCard({
    required this.id,
    required this.name,
    required this.summary,
    required this.uses,
    required this.firstSeenAt,
    this.lastSeenAt,
    this.timesSeen = 1,
    this.photoPath,
    this.status = MachineCardStatus.preparing,
    this.recognisedAs,
    this.confidence,
  });

  /// Stable across sightings, derived from the name so photographing the same
  /// machine twice updates one card rather than making a second.
  final String id;

  /// What the model called it, in the user's language.
  final String name;

  /// One or two sentences: what this machine is and what it trains.
  final String summary;

  /// What can be done on it. Plain text, not exercise ids — we have no clips
  /// for these yet, and pretending otherwise is what the catalog rule forbids.
  final List<String> uses;

  final DateTime firstSeenAt;
  final DateTime? lastSeenAt;

  /// How often this machine has been photographed. The number that decides
  /// which missing content is worth filming first.
  final int timesSeen;

  /// The user's own photo, on their device.
  final String? photoPath;

  final MachineCardStatus status;

  /// What the recogniser thought before falling through to "unknown", when it
  /// offered anything at all. Kept because a card whose model was 40% sure of
  /// a lat pulldown is a different piece of evidence from one it had no idea
  /// about, and only the log can tell them apart later.
  final String? recognisedAs;
  final double? confidence;

  /// What to search for when offering an outside video.
  ///
  /// The app has no clip for this machine and will not have one today, so
  /// sending the user somewhere that does is more useful than an empty page.
  /// Operator: *"а клиенту посоветовать ролик на ютюбе или еще где пока мы не
  /// добавим новый контент"*.
  String get searchQuery => '$name exercises technique';

  MachineCard seenAgain(DateTime at, {String? photoPath}) => MachineCard(
        id: id,
        name: name,
        summary: summary,
        uses: uses,
        firstSeenAt: firstSeenAt,
        lastSeenAt: at,
        timesSeen: timesSeen + 1,
        // The newer photo wins only if there is one: a sighting from a session
        // where the image could not be kept must not erase the one we have.
        photoPath: photoPath ?? this.photoPath,
        status: status,
        recognisedAs: recognisedAs,
        confidence: confidence,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'summary': summary,
        'uses': uses,
        'firstSeenAt': firstSeenAt.toUtc().toIso8601String(),
        if (lastSeenAt != null)
          'lastSeenAt': lastSeenAt!.toUtc().toIso8601String(),
        'timesSeen': timesSeen,
        if (photoPath != null) 'photoPath': photoPath,
        'status': status.name,
        if (recognisedAs != null) 'recognisedAs': recognisedAs,
        if (confidence != null) 'confidence': confidence,
      };

  static MachineCard fromJson(Map<String, dynamic> j) => MachineCard(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        uses: (j['uses'] as List?)?.cast<String>() ?? const [],
        firstSeenAt:
            DateTime.tryParse(j['firstSeenAt'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        lastSeenAt: DateTime.tryParse(j['lastSeenAt'] as String? ?? '')?.toLocal(),
        timesSeen: (j['timesSeen'] as num?)?.toInt() ?? 1,
        photoPath: j['photoPath'] as String?,
        // An unrecognised status name must not lose the card. A build that
        // writes a status this one has never heard of is a reason to show the
        // card as still-preparing, not to drop the user's machine.
        status: MachineCardStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => MachineCardStatus.preparing,
        ),
        recognisedAs: j['recognisedAs'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is MachineCard &&
      other.id == id &&
      other.name == name &&
      other.summary == summary &&
      listEquals(other.uses, uses) &&
      other.firstSeenAt == firstSeenAt &&
      other.lastSeenAt == lastSeenAt &&
      other.timesSeen == timesSeen &&
      other.photoPath == photoPath &&
      other.status == status &&
      other.recognisedAs == recognisedAs &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(id, name, summary, Object.hashAll(uses),
      firstSeenAt, lastSeenAt, timesSeen, photoPath, status, recognisedAs,
      confidence);
}

/// What the app is able to offer for a photographed machine.
enum MachineCardStatus {
  /// Recognised, described, no clip yet. What the user sees is the description
  /// and an honest label saying the demonstration is being prepared.
  preparing,

  /// Someone has since added it to the catalog. The card stops being the
  /// answer and the catalog entry takes over.
  inCatalog,

  /// Looked at and declined — not gym equipment, or too niche to film.
  /// Recorded so the same photograph does not re-open the same question.
  declined,
}

/// Derives the stable id for a machine name.
///
/// Case and spacing are normalised so "Lat Pulldown", "lat  pulldown" and
/// "LAT PULLDOWN" are one machine. Two people photographing the same thing in
/// two gyms should raise the count on one card, because that count is what
/// decides which missing content gets filmed first.
///
/// Also relied on by `equipment/data/equipment_setup_note.dart`'s
/// `equipmentSetupNoteId` (Gate G) to slug a gym name into a Firestore doc-id
/// component -- for a wholly unrelated reason (the gym half of a setup
/// note's composite key, not machine-name dedup). Changing this function's
/// normalisation for a machine-card reason changes that feature's doc ids
/// too, silently orphaning any previously-saved setup note whose gym name is
/// affected -- `get()` on the old id just returns null, no error.
/// `equipment_setup_note_test.dart` pins fixed inputs/outputs of this
/// function specifically to catch that drift; update those pins deliberately
/// if this normalisation ever changes.
String machineCardId(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9Ѐ-ӿ]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'machine' : slug;
}
