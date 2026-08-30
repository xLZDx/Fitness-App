import 'equipment_alias_index.dart';

/// Resolves a free-text exercise suggestion to the real catalogue exercise
/// it names, or to nothing.
///
/// G-C/F016: `MachineDescriber` invents a `uses[]` list of exercise names for
/// an unrecognised machine, with nothing checking whether any of them are
/// real. The user-facing safety boundary is the widget that renders those
/// suggestions (`machine_card_view.dart`), which re-validates on every
/// render regardless of how or when the underlying record reached it (a
/// fresh scan, a stored/legacy record streamed from Firestore, anything
/// future that writes one without going through the scan flow at all) —
/// see that widget's own doc comment for why write-time-only filtering was
/// tried first and rejected.
///
/// [resolve] returns the matched CATALOGUE title, never the free text that
/// matched it. GPT-PM's round-19 review caught why a boolean `matches()` was
/// unsafe on its own: the model is free to elaborate on a real title with an
/// invented modification — "Leg Press With Torso Rotation" contains the real
/// title "Leg Press" as a whole-word phrase, so a boolean check would accept
/// the line and a naive filter would then render the WHOLE line, smuggling
/// the invented "With Torso Rotation" straight past the check it just
/// passed. Returning the canonical title and discarding everything else the
/// model wrote closes that: only real catalogue text can ever reach the
/// screen for a "validated" line, never the model's own words.
///
/// Mirrors [EquipmentAliasIndex]'s normalisation and whole-word phrase-match
/// rule deliberately: same alphabet, same "the model tends to elaborate
/// rather than shorten a real name" shape, and this codebase has already
/// leaned on that exact rule for a structurally identical free-text-to-
/// catalogue problem — extended here to also mirror its RETURN shape
/// (resolve to the canonical value, not a bare bool) for the reason above.
class ExerciseNameMatcher {
  ExerciseNameMatcher(Iterable<String> catalogueTitles)
      : _byNormalised = {
          for (final title in catalogueTitles)
            if (EquipmentAliasIndex.normalise(title).isNotEmpty)
              EquipmentAliasIndex.normalise(title): title,
        };

  /// Normalised catalogue title -> the real, displayable title it came from.
  final Map<String, String> _byNormalised;

  /// The canonical catalogue title [freeText] names, or contains as a
  /// whole-word phrase, or null when nothing in the catalogue matches.
  ///
  /// Phrase match, not a loose substring: [freeText] is padded with spaces
  /// before the check, so a title only counts as present when it appears on
  /// a word boundary (mirrors [EquipmentAliasIndex.resolve]'s own guard —
  /// without it, a short title like "leg" could falsely license "leg press"
  /// text that never actually names "leg" as a title). The longest matching
  /// title wins, same tie-break as [EquipmentAliasIndex.resolve], so a more
  /// specific catalogue entry is preferred over a shorter one it contains.
  String? resolve(String freeText) {
    final text = EquipmentAliasIndex.normalise(freeText);
    if (text.isEmpty) return null;
    final direct = _byNormalised[text];
    if (direct != null) return direct;

    String? bestTitle;
    var bestLen = 0;
    final padded = ' $text ';
    for (final entry in _byNormalised.entries) {
      if (entry.key.length <= bestLen) continue;
      if (padded.contains(' ${entry.key} ')) {
        bestTitle = entry.value;
        bestLen = entry.key.length;
      }
    }
    return bestTitle;
  }

  /// Whether [freeText] resolves to anything in the catalogue.
  bool matches(String freeText) => resolve(freeText) != null;

  /// [lines] resolved to their canonical catalogue titles, dropping any line
  /// that resolves to nothing. Never returns a line's own original text —
  /// see [resolve] for why that matters.
  List<String> filter(Iterable<String> lines) {
    final out = <String>[];
    for (final line in lines) {
      final resolved = resolve(line);
      if (resolved != null) out.add(resolved);
    }
    return out;
  }
}
