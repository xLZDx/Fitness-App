/// Holds the pure flow state (`nextFlow`) for the scan screens and exposes the
/// effects it asks for. It executes NO effect itself: the job runner (C14/C16)
/// listens to [ScanFlowSnapshot.effects] and reports back with events.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/body_scan_flow_machine.dart';

class ScanFlowSnapshot {
  const ScanFlowSnapshot({
    this.state = const FlowState.idle(),
    this.effects = const [],
    this.context = const FlowContext(),
    this.revision = 0,
  });

  final FlowState state;

  /// Effects requested by the LAST transition.
  final List<FlowEffect> effects;
  final FlowContext context;

  /// Increments on every dispatch so a listener sees repeated equal effects.
  final int revision;
}

class ScanFlowController extends StateNotifier<ScanFlowSnapshot> {
  ScanFlowController() : super(const ScanFlowSnapshot());

  void updateContext(FlowContext context) {
    state = ScanFlowSnapshot(
      state: state.state,
      effects: const [],
      context: context,
      revision: state.revision,
    );
  }

  void dispatch(FlowEvent event) {
    final t = nextFlow(state.state, event, state.context);
    state = ScanFlowSnapshot(
      state: t.state,
      effects: t.effects,
      context: state.context,
      revision: state.revision + 1,
    );
  }

  /// Back to idle, e.g. when the page is left.
  void reset() => state = ScanFlowSnapshot(context: state.context);
}

final scanFlowControllerProvider =
    StateNotifierProvider.autoDispose<ScanFlowController, ScanFlowSnapshot>(
  (_) => ScanFlowController(),
);
