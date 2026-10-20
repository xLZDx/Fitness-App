/// Tunable numbers of the recorder state machine (S04 design 5.4, 8.1). All
/// values are PROPOSED. Pipeline numbers live in
/// `pipeline/recording_constants.dart` (lane R3) and are reused from there.
library;

/// `preparing` becomes the `cannotStart` panel after this long (S04-34 AC-2).
const int kPreparingTimeoutMs = 5000;

/// The `startFailed` panel appears when journal `begin()` plus the location
/// start call take longer than this (S04-34 AC-2, counted from the start call).
const int kStartFailedTimeoutMs = 15000;

/// Period of the recorder tick that advances pipeline time without a fix.
const int kRecorderTickMs = 1000;

/// Battery critical is entered at or below this percent when not charging
/// (S04-22).
const int kBatteryCriticalPercent = 10;

/// Battery critical is left at charging or at this percent (hysteresis).
const int kBatteryCriticalExitPercent = 12;

/// At or below this percent, not charging, the recorder finishes and saves
/// with the reason `battery` (S04-22 AC-1).
const int kBatteryFinishPercent = 3;

/// Journal flush interval in normal operation and at battery critical
/// (design 4.4, S04-R-030). The journal lane applies it.
const int kFlushIntervalMs = 5000;
const int kBatteryCriticalFlushIntervalMs = 1000;

/// Maximum kept samples before the automatic stop `sampleCap` (design 5.5).
const int kSampleCap = 190000;

/// Grace period after the engine detached before the service stops, used only
/// by `EngineDetachPolicy.graceThenStop` (design 5.6, S04-37 option b).
const int kEngineDetachGraceMs = 60000;
