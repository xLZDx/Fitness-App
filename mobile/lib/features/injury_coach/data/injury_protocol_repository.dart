import 'injury_protocol.dart';

abstract class InjuryProtocolRepository {
  /// All protocols whose [InjuryProtocol.targetInjuries] intersect with
  /// the user's reported injuries.
  Future<List<InjuryProtocol>> matchFor(Iterable<String> reportedInjuries);

  /// Lookup by stable id.
  Future<InjuryProtocol?> byId(String id);

  /// Currently-active protocol (if the user is following one).
  Future<String?> activeProtocolId(String uid);

  Future<void> startProtocol(String uid, String protocolId);
  Future<void> endProtocol(String uid);
}

class MockInjuryProtocolRepository implements InjuryProtocolRepository {
  MockInjuryProtocolRepository();

  static final List<InjuryProtocol> _seed = [
    InjuryProtocol(
      id: 'low-back-strain-acute',
      title: 'Low-back strain — acute (weeks 1–3)',
      targetInjuries: const ['low_back_strain', 'lumbar_strain'],
      reviewedBy: 'community',
      summary: 'Volume-managed return-to-load plan. Avoids spinal '
          'flexion + heavy axial loading; emphasises hip-hinge motor '
          'control with isometrics → tempo squats → hinge variants.',
      weeks: [
        InjuryProtocolWeek(
          weekNumber: 1,
          intentLine: 'Calm down. Hip-hinge motor control only.',
          days: [
            InjuryProtocolDay(
                dayNumber: 1, exerciseIds: const ['glute_bridge', 'plank']),
            InjuryProtocolDay(dayNumber: 2, exerciseIds: const [], restDay: true),
            InjuryProtocolDay(
                dayNumber: 3, exerciseIds: const ['glute_bridge', 'birddog']),
            InjuryProtocolDay(dayNumber: 4, exerciseIds: const [], restDay: true),
            InjuryProtocolDay(
                dayNumber: 5, exerciseIds: const ['glute_bridge', 'plank']),
            InjuryProtocolDay(dayNumber: 6, exerciseIds: const [], restDay: true),
            InjuryProtocolDay(
                dayNumber: 7,
                exerciseIds: const [],
                restDay: true,
                note: 'Walk 20 minutes if pain-free.'),
          ],
        ),
      ],
      contraindicationsAdded: const ['heavy_axial_load', 'spinal_flexion'],
    ),
    InjuryProtocol(
      id: 'shoulder-impingement-mild',
      title: 'Shoulder impingement — mild (weeks 1–4)',
      targetInjuries: const ['shoulder_impingement'],
      reviewedBy: 'community',
      summary: 'Restore scapular control with band external rotations + '
          'serratus push-ups before re-introducing overhead work. Strict '
          'no-overhead rule for the first two weeks.',
      weeks: [
        InjuryProtocolWeek(
          weekNumber: 1,
          intentLine: 'No overhead. Wake up the rotator cuff.',
          days: [
            InjuryProtocolDay(
                dayNumber: 1,
                exerciseIds: const [
                  'band_external_rotation',
                  'serratus_pushup'
                ]),
            InjuryProtocolDay(dayNumber: 2, exerciseIds: const [], restDay: true),
            InjuryProtocolDay(
                dayNumber: 3,
                exerciseIds: const [
                  'band_external_rotation',
                  'wall_slide'
                ]),
            InjuryProtocolDay(dayNumber: 4, exerciseIds: const [], restDay: true),
            InjuryProtocolDay(
                dayNumber: 5,
                exerciseIds: const [
                  'band_external_rotation',
                  'serratus_pushup'
                ]),
            InjuryProtocolDay(dayNumber: 6, exerciseIds: const [], restDay: true),
            InjuryProtocolDay(dayNumber: 7, exerciseIds: const [], restDay: true),
          ],
        ),
      ],
      contraindicationsAdded: const ['overhead_press', 'overhead_pull'],
    ),
  ];

  final Map<String, String> _activeByUid = {};

  @override
  Future<List<InjuryProtocol>> matchFor(
      Iterable<String> reportedInjuries) async {
    final set = reportedInjuries.toSet();
    return _seed
        .where((p) =>
            p.targetInjuries.any((i) => set.contains(i)))
        .toList();
  }

  @override
  Future<InjuryProtocol?> byId(String id) async {
    for (final p in _seed) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<String?> activeProtocolId(String uid) async => _activeByUid[uid];

  @override
  Future<void> startProtocol(String uid, String protocolId) async {
    _activeByUid[uid] = protocolId;
  }

  @override
  Future<void> endProtocol(String uid) async {
    _activeByUid.remove(uid);
  }
}
