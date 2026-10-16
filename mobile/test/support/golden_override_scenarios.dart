// The literal ORACLE of the override scenarios (S02 test plan 1.16). Hand
// authored; imports nothing from the production override code, the recompute
// function or the repository. U41 compares the production code against these
// rows; no expectation is ever derived from production code.
//
// Common setup of every row (field `distanceM`): last synced base 4 800 at rev
// N = 7; device A wrote 5 000 at rev N + 1 = 8; device B holds a stale record
// recomputing 4 800 and holds the override
// {value 5 000, atComputed 4 800, atVersions V1, atRev 8}; baseSummary 5 000.

/// Literal calculation-version triples (formula, metricDefinition, threshold).
const List<String> kV1 = ['f1', 'm1', 't1'];
const List<String> kV2 = ['f2', 'm1', 't1'];
const List<String> kV3 = ['f3', 'm1', 't1'];

/// How the server and the local value meet in the three-way merge.
enum MergeOutcome {
  /// Merged, and the merged value is [OverrideRow.mergedValue].
  merged,

  /// Both sides changed the field to different values.
  conflict,
}

class OverrideRow {
  const OverrideRow({
    required this.id,
    required this.kind,
    required this.event,
    required this.inForce,
    required this.rawAfter,
    required this.server,
    required this.kept,
    required this.written,
    required this.outcome,
    this.mergedValue,
    this.atComputed,
    this.atVersions,
    this.candidate,
    this.adopted = false,
  });

  /// Oracle row id (G1 ...).
  final String id;

  /// P passive, X explicit edit, R recalculation (plan 1.16).
  final String kind;

  /// Event name the test driver maps to a record mutation.
  final String event;

  /// The version triple in force after the event.
  final List<String> inForce;

  /// `recompute` after the event (the raw derivation).
  final double rawAfter;

  /// The server value of `distanceM` at the merge.
  final double server;

  /// Whether the override is KEPT after the event.
  final bool kept;

  /// The written `distanceM`.
  final double written;

  final MergeOutcome outcome;

  /// The merged value when [outcome] is merged.
  final double? mergedValue;

  /// Expected `atComputed` / `atVersions` / `recalcCandidate` of a kept override.
  final double? atComputed;
  final List<String>? atVersions;
  final double? candidate;

  /// True when the merge must report the field as a server-only adoption.
  final bool adopted;
}

const List<OverrideRow> kOverrideRows = [
  OverrideRow(id: 'G1', kind: 'P', event: 'synced marker', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G2', kind: 'P', event: 'baseRev and baseSummary updated', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G3', kind: 'P', event: 'queue state, repeated synced', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G4', kind: 'P', event: 'lost acknowledgement replay', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G5', kind: 'P', event: 'new commit generation', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G6', kind: 'P', event: 'restart', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G7', kind: 'P', event: 'merge note added', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G8', kind: 'P', event: 'provenance changed', inForce: kV1, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV1),
  OverrideRow(id: 'G9', kind: 'R', event: 'versions only', inForce: kV2, rawAfter: 4800, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4800, atVersions: kV2),
  OverrideRow(id: 'G10', kind: 'P', event: 'input change', inForce: kV1, rawAfter: 5100, server: 5000, kept: false, written: 5100, outcome: MergeOutcome.merged, mergedValue: 5100),
  OverrideRow(id: 'G11', kind: 'P', event: 'input change', inForce: kV1, rawAfter: 5100, server: 5200, kept: false, written: 5100, outcome: MergeOutcome.conflict),
  OverrideRow(id: 'G12', kind: 'P', event: 'input change', inForce: kV1, rawAfter: 5100, server: 5100, kept: false, written: 5100, outcome: MergeOutcome.merged, mergedValue: 5100),
  OverrideRow(id: 'G13', kind: 'P', event: 'input change', inForce: kV1, rawAfter: 5000, server: 5000, kept: false, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000),
  OverrideRow(id: 'G14', kind: 'R', event: 'input change', inForce: kV2, rawAfter: 4830, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 4830, atVersions: kV2, candidate: 4830),
  OverrideRow(id: 'G17', kind: 'R', event: 'input change', inForce: kV2, rawAfter: 4830, server: 5400, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5400, atComputed: 4830, atVersions: kV2, candidate: 4830, adopted: true),
  OverrideRow(id: 'G27', kind: 'R', event: 'input change', inForce: kV2, rawAfter: 5100, server: 5000, kept: true, written: 5000, outcome: MergeOutcome.merged, mergedValue: 5000, atComputed: 5100, atVersions: kV2, candidate: 5100),
];
