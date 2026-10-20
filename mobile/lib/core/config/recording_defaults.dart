/// Privacy and release constants of the GPS recorder (S04 design 9.3, stories
/// S04-21 and S04-28). Nothing in S04 applies the privacy-zone or expiry values:
/// they are defaults for a later sprint that shares or uploads a route.
library;

/// Default privacy-zone radius in metres, applied when a route is SHARED or
/// exported outside the device by a later sprint, never at storage (S04-R-048,
/// design 9.3). PROPOSED value.
const int kDefaultPrivacyZoneRadiusM = 200;

/// Settings key of the privacy-zone default (S04-D 18). Read-only in S04.
const String kPrivacyZoneSettingKey = 'settings.privacyZone';

/// Settings key of the consent row in Settings, Privacy (S04-D 18.1).
const String kGpsConsentSettingKey = 'settings.gpsConsent';

/// Default expiry of an uploaded GPS track in months counted from the activity
/// date (S04-R-049). PROPOSED value; enforced by nothing in S04.
const int kDefaultGpsExpiryMonths = 24;

/// Upload of GPS tracks is off in S04 (S04-R-046). The recorder never reads a
/// cloud flag; a test asserts this constant and that no upload entry point is
/// reachable from the recorder.
const bool kGpsUploadEnabled = false;

/// The recorder never records heart rate (S04-R-050).
const bool kRecorderRecordsHeartRate = false;

/// ARB key of the saved-on-device notice (S04-R-047). Removed only by the
/// sprint that enables upload.
const String kSavedOnDeviceStringKey = 'gpsSavedOnDevice';

/// Text version of the DRAFT location wording. It must equal the ARB value of
/// `gpsConsentTextVersion` in every locale (S04-21 AC-3); bump both together
/// when the wording changes.
const String kLocationConsentTextVersion = 'draft-1';

/// Prefix of the per-account consent key. It starts with `activity.` and ends
/// with `.<uid>` so the device wipe erases it (design 6.2). Not the
/// cloud-streams consent key (`activity.cloudStreamsConsent.<uid>`).
const String kLocationConsentKeyPrefix = 'activity.locationConsent.v1.';

/// SharedPreferences key of one account's location consent.
String locationConsentKeyFor(String uid) => '$kLocationConsentKeyPrefix$uid';
