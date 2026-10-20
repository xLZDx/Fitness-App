// Review round 1, batch FIX-A: controller findings C1, C7, C8 (one focused test
// each) on the shared recorder world.
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/recorder_world.dart';

Future<RecorderWorld> _revoked() async {
  final w = RecorderWorld.create();
  await w.start();
  await w.walk(5);
  w.permissions.location = LocationPermissionStatus.denied;
  await w.advance(const Duration(seconds: 2));
  expect(w.phase, RecorderPhase.permissionRevoked);
  return w;
}

void main() {
  test('C1 a failed collection start releases the journal (abandonActive)', () async {
    final w = RecorderWorld.create();
    w.location.startError = StateError('no service');
    await w.start();
    await w.advance(const Duration(seconds: 1));
    expect(w.phase, RecorderPhase.idle);
    expect(w.journal.abandoned, isNotEmpty,
        reason: 'begin succeeded, so the active recording must be released');
    await w.dispose();
  });

  test('C7 a confirmed account change resets a stale finished phase', () async {
    final w = RecorderWorld.create();
    await w.start();
    await w.walk(5);
    await w.stop();
    await w.advance(const Duration(seconds: 2));
    expect(w.phase, RecorderPhase.finished);
    w.controller.onAccountChanged('a');
    w.controller.onAccountChanged('b');
    expect(w.phase, RecorderPhase.idle);
    expect(w.state.recordingId, isNull);
    await w.dispose();
  });

  test('C8 Keep when DELETE already won completes the delete and says so', () async {
    final w = await _revoked();
    w.journal.keepOutcome = DecisionOutcome.alreadyDecided;
    await w.run(() => w.controller.keepRevoked());
    expect(w.journal.deletes, isNotEmpty, reason: 'the winner (DELETE) is completed');
    expect(w.phase, RecorderPhase.idle);
    expect(w.state.lastActionResult, RecorderActionResult.alreadyDecided);
    await w.dispose();
  });

  test('C8 a thrown decision is reported as failed and the phase stays', () async {
    final w = await _revoked();
    w.journal.decideError = StateError('io');
    await w.run(() => w.controller.deleteRevoked());
    expect(w.phase, RecorderPhase.permissionRevoked);
    expect(w.state.lastActionResult, RecorderActionResult.failed);
    await w.dispose();
  });
}
