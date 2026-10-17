/// The Start and Resume permission journey of the GPS recording (S04-D 6, 7;
/// S04-17, S04-34; S04-R-021, -023, -054, -055).
///
/// One notifier owns the order of calls: consent, device checks, unfinished
/// check, battery, services, location status, pre-prompt, location request,
/// notification request, then the recorder's own Start (RS-3, RS-7, RS-11).
/// Opening the screen performs no permission or location call (RS-1): nothing
/// here runs until [GpsStartFlow.start] or [GpsStartFlow.resume] is called from
/// a button.
///
/// The recorder keeps its own panel state (`preparing`, `cannotStart`,
/// `startFailed`); this notifier adds the permission panels. The page shows
/// [gpsEffectivePanel].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/data/sport_type.dart';
import '../consent/location_consent.dart';
import '../consent/location_consent_providers.dart';
import '../permissions/location_permission_status.dart';
import '../permissions/permission_providers.dart';
import '../state/battery_monitor.dart';
import '../state/recorder_phase.dart';
import '../state/recorder_providers.dart';
import '../state/recorder_state_constants.dart';

/// Panel ids of the Start screen (S04-D 6, keys `gps.start.panel.<id>`).
enum GpsStartPanelId {
  none,
  preprompt,
  preparing,
  cannotStart,
  startFailed,
  consentWithdrawn,
  restricted,
  deniedOnce,
  deniedForever,
  approximateOnly,
  servicesOff,
  notifOff,
  noGps,
  blockedByJournal,
  batteryTooLow,
  gymTimerRunning,
}

/// Panel precedence when several apply, highest first (RS-11).
const List<GpsStartPanelId> kGpsPanelPrecedence = <GpsStartPanelId>[
  GpsStartPanelId.consentWithdrawn,
  GpsStartPanelId.blockedByJournal,
  GpsStartPanelId.preparing,
  GpsStartPanelId.cannotStart,
  GpsStartPanelId.gymTimerRunning,
  GpsStartPanelId.batteryTooLow,
  GpsStartPanelId.noGps,
  GpsStartPanelId.restricted,
  GpsStartPanelId.servicesOff,
  GpsStartPanelId.deniedForever,
  GpsStartPanelId.approximateOnly,
  GpsStartPanelId.deniedOnce,
  GpsStartPanelId.preprompt,
  GpsStartPanelId.notifOff,
  GpsStartPanelId.startFailed,
];

// ------------------------------------------------------------------- seams

/// Whether the phone's location services are on. Default: assumed on (the
/// recorder lane has no probe yet); lane R9 overrides it when a probe exists.
final gpsLocationServicesEnabledProvider =
    Provider<Future<bool> Function()>((ref) => () async => true);

/// Whether the device reports GPS hardware (DN-13). Default: true.
final gpsDeviceHasGpsProvider = Provider<bool>((ref) => true);

/// Opens the system location settings page (not a permission request).
/// Default falls back to the app settings page of the permission service.
final gpsOpenLocationSettingsProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ref.read(permissionServiceProvider).openSettings();
  },
);

/// Set when a Stop in a fresh `acquiring` saved nothing; the Start screen shows
/// `gpsNothingRecorded` once.
final gpsNothingRecordedProvider = StateProvider<bool>((ref) => false);

/// Battery reading for the Start note and the too-low panel (RS-5). Reading it
/// makes no permission or location call.
final gpsStartBatteryProvider =
    FutureProvider.autoDispose<BatteryReading?>((ref) async {
  try {
    return await ref.watch(batteryMonitorProvider).current();
  } catch (_) {
    return null;
  }
});

/// Live battery percent for the recording banner; null when unknown.
final gpsLiveBatteryProvider = StreamProvider.autoDispose<BatteryReading>((ref) {
  try {
    return ref.watch(batteryMonitorProvider).readings;
  } catch (_) {
    return const Stream<BatteryReading>.empty();
  }
});

// ------------------------------------------------------------------- state

class GpsStartFlowState {
  const GpsStartFlowState({
    this.panel = GpsStartPanelId.none,
    this.working = false,
    this.notifPermanent = false,
    this.started = false,
  });

  /// The permission-side panel (the recorder's own panel is merged by
  /// [gpsEffectivePanel]).
  final GpsStartPanelId panel;

  /// A start is in progress: the button reads `gpsStarting` and is disabled
  /// (RS-6).
  final bool working;

  /// Notification permission is permanently denied: `notifOff` offers Open
  /// settings instead of Allow (S04-D 7).
  final bool notifPermanent;

  /// The user tapped Start or Resume at least once on this screen (RS-4).
  final bool started;

  GpsStartFlowState copyWith({
    GpsStartPanelId? panel,
    bool? working,
    bool? notifPermanent,
    bool? started,
  }) =>
      GpsStartFlowState(
        panel: panel ?? this.panel,
        working: working ?? this.working,
        notifPermanent: notifPermanent ?? this.notifPermanent,
        started: started ?? this.started,
      );
}

final gpsStartFlowProvider =
    NotifierProvider.autoDispose<GpsStartFlow, GpsStartFlowState>(
        GpsStartFlow.new);

/// The one panel to show: the recorder's busy/failed panels win, then the
/// permission panel (RS-11 keeps the order inside each source).
GpsStartPanelId gpsEffectivePanel(GpsStartFlowState flow, StartPanel recorder) {
  final fromRecorder = switch (recorder) {
    StartPanel.preparing => GpsStartPanelId.preparing,
    StartPanel.cannotStart => GpsStartPanelId.cannotStart,
    StartPanel.startFailed => GpsStartPanelId.startFailed,
    StartPanel.none => GpsStartPanelId.none,
  };
  final candidates = <GpsStartPanelId>[flow.panel, fromRecorder]
      .where((p) => p != GpsStartPanelId.none)
      .toList();
  if (candidates.isEmpty) return GpsStartPanelId.none;
  candidates.sort((a, b) => kGpsPanelPrecedence
      .indexOf(a)
      .compareTo(kGpsPanelPrecedence.indexOf(b)));
  return candidates.first;
}

class GpsStartFlow extends AutoDisposeNotifier<GpsStartFlowState> {
  bool _alive = true;
  bool _prePromptDone = false;
  bool _forceLocationRequest = false;
  bool _notifRefused = false;
  bool _notifAllowTap = false;

  SportType _sport = SportType.walking;
  bool? _autoPause;
  String? _resumeId;

  @override
  GpsStartFlowState build() {
    ref.onDispose(() => _alive = false);
    return const GpsStartFlowState();
  }

  void _set(GpsStartFlowState Function(GpsStartFlowState) edit) {
    if (_alive) state = edit(state);
  }

  // -------------------------------------------------------------- entries

  /// The Start button. Never called by opening the screen.
  Future<void> start({required SportType sport, required bool autoPause}) {
    _sport = sport;
    _autoPause = autoPause;
    _resumeId = null;
    return _run();
  }

  /// The Resume button of resume mode (RS-8). [recordingId] is the readable
  /// unfinished recording being resumed.
  Future<void> resume(String recordingId) {
    _resumeId = recordingId;
    return _run();
  }

  /// Pre-prompt "Continue": records the consent first (RS-10, fail closed),
  /// then asks the system once.
  Future<void> continuePrePrompt() async {
    if (state.working) return;
    _set((s) => s.copyWith(working: true));
    bool ok;
    try {
      ok = await ref.read(locationConsentProvider.notifier).grant();
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _set((s) =>
          s.copyWith(working: false, panel: GpsStartPanelId.cannotStart));
      return;
    }
    _prePromptDone = true;
    _set((s) => s.copyWith(working: false));
    await _run();
  }

  /// Pre-prompt "Not now": writes nothing and sends no request.
  void declinePrePrompt() {
    _set((s) => s.copyWith(panel: GpsStartPanelId.none, started: false));
  }

  /// "Try again" on `deniedOnce` (one more system request), `cannotStart` and
  /// `startFailed` (one start per tap).
  Future<void> tryAgain() {
    if (state.panel == GpsStartPanelId.deniedOnce) {
      _forceLocationRequest = true;
    }
    ref.read(recorderControllerProvider.notifier).dismissStartPanel();
    return _run();
  }

  /// "Allow notifications" on `notifOff` (one request) or Open settings.
  Future<void> allowNotifications() {
    _notifRefused = false;
    _notifAllowTap = true;
    return _run();
  }

  /// RS-4: the app returned to the foreground; a user who fixed the problem in
  /// settings continues without another tap.
  Future<void> recheck() async {
    if (!state.started || state.working) return;
    const settingsPanels = <GpsStartPanelId>{
      GpsStartPanelId.deniedForever,
      GpsStartPanelId.approximateOnly,
      GpsStartPanelId.servicesOff,
      GpsStartPanelId.notifOff,
      GpsStartPanelId.restricted,
    };
    if (!settingsPanels.contains(state.panel)) return;
    if (state.panel == GpsStartPanelId.notifOff) _notifRefused = false;
    await _run();
  }

  Future<void> openSettings() async {
    try {
      await ref.read(permissionServiceProvider).openSettings();
    } catch (_) {
      // Nothing to do: the panel stays and the user can go back.
    }
  }

  Future<void> openLocationSettings() async {
    try {
      await ref.read(gpsOpenLocationSettingsProvider)();
    } catch (_) {
      // Same as above.
    }
  }

  // ---------------------------------------------------------------- the run

  Future<void> _run() async {
    if (state.working) return;
    _set((s) => s.copyWith(working: true, started: true));
    try {
      final next = await _evaluate();
      _set((s) => s.copyWith(panel: next));
    } catch (_) {
      _set((s) => s.copyWith(panel: GpsStartPanelId.cannotStart));
    } finally {
      _set((s) => s.copyWith(working: false));
    }
  }

  /// Returns the panel that explains why the start cannot proceed, or
  /// [GpsStartPanelId.none] when the recorder was started or resumed.
  Future<GpsStartPanelId> _evaluate() async {
    final resuming = _resumeId != null;

    // 1. Consent withdrawn (RS-7, RS-8).
    LocationConsent consent;
    try {
      consent = await ref.read(locationConsentProvider.future);
    } catch (_) {
      return GpsStartPanelId.cannotStart;
    }
    final consentState = consent.recordingState;
    if (consentState == ConsentState.withdrawn) {
      return GpsStartPanelId.consentWithdrawn;
    }

    // 2. Device checks.
    if (!ref.read(gpsDeviceHasGpsProvider)) return GpsStartPanelId.noGps;
    final recorder = ref.read(recorderControllerProvider.notifier);

    // 3. Unfinished recording blocks a fresh Start (not Resume, RS-8).
    if (!resuming) {
      try {
        final list = await ref.read(recordingJournalPortProvider).listUnfinished();
        if (list.any((u) => u.blocksStart)) {
          return GpsStartPanelId.blockedByJournal;
        }
      } catch (_) {
        return GpsStartPanelId.cannotStart;
      }
    }

    // 4. Battery at or below 3 percent and not charging.
    try {
      final r = await ref.read(batteryMonitorProvider).current();
      if (r != null && !r.charging && r.percent <= kBatteryFinishPercent) {
        return GpsStartPanelId.batteryTooLow;
      }
    } catch (_) {
      // No reading: Start still works.
    }

    // 5. Location services.
    bool servicesOn = true;
    try {
      servicesOn = await ref.read(gpsLocationServicesEnabledProvider)();
    } catch (_) {
      servicesOn = true;
    }
    if (!servicesOn) return GpsStartPanelId.servicesOff;

    // 6. Location permission.
    final perms = ref.read(permissionServiceProvider);
    var status = await perms.locationStatus();
    switch (status) {
      case LocationPermissionStatus.restricted:
        return GpsStartPanelId.restricted;
      case LocationPermissionStatus.permanentlyDenied:
        return GpsStartPanelId.deniedForever;
      case LocationPermissionStatus.grantedApproximate:
        return GpsStartPanelId.approximateOnly;
      case LocationPermissionStatus.denied:
      case LocationPermissionStatus.grantedPrecise:
        break;
    }
    final needsConsent = consentState != ConsentState.granted;
    final needsRequest = status == LocationPermissionStatus.denied;
    if ((needsConsent || needsRequest) && !_prePromptDone && !_forceLocationRequest) {
      return GpsStartPanelId.preprompt;
    }
    if (needsRequest) {
      _forceLocationRequest = false;
      status = await perms.requestLocation();
      switch (status) {
        case LocationPermissionStatus.grantedPrecise:
          break;
        case LocationPermissionStatus.grantedApproximate:
          return GpsStartPanelId.approximateOnly;
        case LocationPermissionStatus.denied:
          return GpsStartPanelId.deniedOnce;
        case LocationPermissionStatus.permanentlyDenied:
          return GpsStartPanelId.deniedForever;
        case LocationPermissionStatus.restricted:
          return GpsStartPanelId.restricted;
      }
    }

    // 7. Notification permission (Android 13+), asked once.
    final env = ref.read(recorderEnvironmentProvider);
    if (env.requireNotificationPermission) {
      var n = await perms.notificationStatus();
      if (!n.isGranted) {
        final mayAsk = n == NotificationPermissionStatus.denied &&
            (!_notifRefused || _notifAllowTap);
        if (mayAsk) {
          _notifAllowTap = false;
          n = await perms.requestNotification();
        }
        if (!n.isGranted) {
          _notifRefused = true;
          _set((s) => s.copyWith(
              notifPermanent: n == NotificationPermissionStatus.permanentlyDenied));
          return GpsStartPanelId.notifOff;
        }
      }
    }

    // 8. Hand over to the recorder.
    if (resuming) {
      await recorder.resumeRecovered(_resumeId!);
    } else {
      await recorder.requestStart(sport: _sport, autoPauseEnabled: _autoPause);
    }
    return _panelAfterRecorder();
  }

  GpsStartPanelId _panelAfterRecorder() {
    final s = ref.read(recorderControllerProvider);
    if (s.phase == RecorderPhase.acquiring ||
        s.phase == RecorderPhase.preparing) {
      return GpsStartPanelId.none;
    }
    final refusal = s.refusal;
    if (refusal == null) return GpsStartPanelId.none;
    return switch (refusal) {
      StartRefusal.consentMissing => GpsStartPanelId.consentWithdrawn,
      StartRefusal.unfinishedRecording => GpsStartPanelId.blockedByJournal,
      StartRefusal.notificationDenied => GpsStartPanelId.notifOff,
      StartRefusal.permissionNotGranted => GpsStartPanelId.deniedOnce,
      StartRefusal.gymTimerRunning ||
      StartRefusal.foreignSession =>
        GpsStartPanelId.gymTimerRunning,
      StartRefusal.serviceStartFailed => GpsStartPanelId.startFailed,
      StartRefusal.journalNotOpen ||
      StartRefusal.checkIncomplete ||
      StartRefusal.beginFailed =>
        GpsStartPanelId.cannotStart,
    };
  }
}
