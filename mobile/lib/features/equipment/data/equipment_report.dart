/// Categorized fault for an `EquipmentReport`. Mirrors what gym
/// maintenance teams actually triage on — the granularity here drives
/// the eventual webhook routing (broken safety = page on-call, sticker
/// faded = next-week ticket).
enum EquipmentFault {
  /// Cable frayed, cracked plate, missing safety pin — danger.
  unsafe,

  /// Pulley sticky, hydraulic slow, bench wobbly — works but degraded.
  degraded,

  /// QR sticker missing or unreadable — operational, not mechanical.
  qrMissing,

  /// Catch-all for everything else.
  other,
}

class EquipmentReport {
  const EquipmentReport({
    required this.id,
    required this.equipmentId,
    required this.gymId,
    required this.fault,
    required this.note,
    required this.reportedAt,
    required this.reporterUid,
  });

  final String id;
  final String equipmentId;

  /// Optional geo-or-chain id ("anytime_fitness_westwood"). Lets the
  /// webhook route to the right gym's maintenance Slack.
  final String gymId;

  final EquipmentFault fault;
  final String note;
  final DateTime reportedAt;
  final String reporterUid;

  Map<String, dynamic> toJson() => {
        'id': id,
        'equipmentId': equipmentId,
        'gymId': gymId,
        'fault': fault.name,
        'note': note,
        'reportedAt': reportedAt.toIso8601String(),
        'reporterUid': reporterUid,
      };

  factory EquipmentReport.fromJson(Map<String, dynamic> j) {
    final raw = j['reportedAt'];
    DateTime when;
    if (raw is String) {
      when = DateTime.parse(raw);
    } else if (raw is DateTime) {
      when = raw;
    } else {
      throw ArgumentError(
          'reportedAt must be ISO-8601 string or DateTime, got ${raw.runtimeType}');
    }
    final fName = j['fault'] as String? ?? 'other';
    final fault = EquipmentFault.values.firstWhere(
      (f) => f.name == fName,
      orElse: () => EquipmentFault.other,
    );
    return EquipmentReport(
      id: j['id'] as String,
      equipmentId: j['equipmentId'] as String,
      gymId: j['gymId'] as String? ?? 'unknown',
      fault: fault,
      note: j['note'] as String? ?? '',
      reportedAt: when,
      reporterUid: j['reporterUid'] as String,
    );
  }
}
