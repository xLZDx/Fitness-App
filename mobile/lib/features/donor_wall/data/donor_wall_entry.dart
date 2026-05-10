/// A single opt-in donor recognition entry.
///
/// Stored in Firestore under `donor_wall/{uid}` (only writable server-side
/// via the `optInDonorWall` Cloud Function — never the client). The doc id
/// matches the firebase uid so a user can update their own display name +
/// opt-out by re-running the function.
class DonorWallEntry {
  const DonorWallEntry({
    required this.uid,
    required this.displayName,
    required this.tier,
    required this.since,
    this.message,
    this.isLifetime = false,
  });

  final String uid;
  final String displayName;
  final String tier; // "supporter" | "sustainer" | "champion"
  final DateTime since;
  final String? message;
  final bool isLifetime;

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'tier': tier,
        'since': since.toIso8601String(),
        if (message != null) 'message': message,
        if (isLifetime) 'isLifetime': true,
      };

  factory DonorWallEntry.fromJson(String uid, Map<String, dynamic> j) {
    return DonorWallEntry(
      uid: uid,
      displayName:
          (j['displayName'] as String?)?.trim().isNotEmpty == true
              ? j['displayName'] as String
              : 'Anonymous donor',
      tier: (j['tier'] as String?) ?? 'supporter',
      since: DateTime.tryParse(j['since'] as String? ?? '') ??
          DateTime.now(),
      message: (j['message'] as String?)?.trim().isNotEmpty == true
          ? j['message'] as String
          : null,
      isLifetime: j['isLifetime'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DonorWallEntry &&
          other.uid == uid &&
          other.displayName == displayName &&
          other.tier == tier &&
          other.since == since &&
          other.message == message &&
          other.isLifetime == isLifetime;

  @override
  int get hashCode =>
      Object.hash(uid, displayName, tier, since, message, isLifetime);
}
