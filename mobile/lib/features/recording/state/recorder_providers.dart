/// Public providers of the recorder state (S04 design 5, 7.3). The seam
/// providers (journal, environment, battery) live in `recorder_ports.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pipeline/recorder_pipeline.dart';
import 'recorder_controller.dart';
import 'recorder_display.dart';
import 'recorder_phase.dart';
import 'recorder_state.dart';

export 'recorder_ports.dart';

/// The one recorder. Pages, the strip and the notification bridge read and
/// call this; nothing else starts or stops a recording.
final recorderControllerProvider =
    NotifierProvider<RecorderController, RecorderState>(RecorderController.new);

/// Current phase only, so widgets that care about the phase rebuild on phase
/// changes and not on every metrics tick.
final recorderPhaseProvider = Provider<RecorderPhase>(
  (ref) => ref.watch(recorderControllerProvider.select((s) => s.phase)),
);

/// Live numbers of the running recording; null outside a recording.
final recorderLiveMetricsProvider = Provider<LiveMetrics?>(
  (ref) => ref.watch(recorderControllerProvider.select((s) => s.metrics)),
);

/// The three display channels of S04-D 5.3 (headline, banner, chips).
final recorderDisplayProvider = Provider<RecorderDisplay>(
  (ref) => displayOf(ref.watch(recorderControllerProvider)),
);

/// True while the notification may say Recording (design 5.6, S04-37).
final recorderClaimsRecordingProvider = Provider<bool>(
  (ref) =>
      ref.watch(recorderControllerProvider.select((s) => s.claimsRecording)),
);
