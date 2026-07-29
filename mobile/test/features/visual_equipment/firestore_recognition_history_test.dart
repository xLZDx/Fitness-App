import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/firestore_recognition_history.dart';
import 'package:fitness_app/features/visual_equipment/data/recognition_history.dart';

/// These exercise the paths that run BEFORE any Firebase call — the same
/// technique `test/features/auth/firebase_auth_repository_test.dart` uses, and
/// the only one available here: this repo has no `fake_cloud_firestore`,
/// `firebase_auth_mocks` or `mockito` in `dev_dependencies`, and adding one was
/// out of scope. `Timestamp` is a plain value class, so the decode path is
/// fully reachable without a Firebase binding; the signed-out short-circuits in
/// `record` / `list` / `clear` are not, since they need a `FirebaseAuth`
/// instance to report a null `currentUser`.
void main() {
  final t0 = DateTime.utc(2026, 7, 29, 10, 0);

  group('FirestoreRecognitionHistoryRepository construction', () {
    test('constructs without a Firebase binding', () {
      // Firestore/Auth are resolved lazily, so building this as a Riverpod
      // override cannot throw before `Firebase.initializeApp` has run.
      expect(
        () => FirestoreRecognitionHistoryRepository(),
        returnsNormally,
      );
    });

    test('satisfies the shared repository interface', () {
      expect(
        FirestoreRecognitionHistoryRepository(),
        isA<RecognitionHistoryRepository>(),
      );
    });
  });

  group('recognitionEntryFromFirestore', () {
    test('decodes an ISO-8601 recognisedAt', () {
      final entry = recognitionEntryFromFirestore('lat_pulldown', {
        'recognisedAt': t0.toIso8601String(),
        'confidence': 0.77,
        'source': 'live',
      });

      expect(entry.equipmentId, 'lat_pulldown');
      expect(entry.recognisedAt, t0);
      expect(entry.confidence, 0.77);
      expect(entry.source, RecognitionSource.live);
    });

    test('decodes a Firestore Timestamp recognisedAt', () {
      final entry = recognitionEntryFromFirestore('rower', {
        'recognisedAt': Timestamp.fromDate(t0),
        'confidence': 0.5,
      });

      expect(entry.recognisedAt, t0);
      expect(entry.recognisedAt.isUtc, isTrue);
    });

    test('the document id wins over a stale equipmentId field', () {
      final entry = recognitionEntryFromFirestore('bench_press', {
        'equipmentId': 'renamed_long_ago',
        'recognisedAt': t0.toIso8601String(),
        'confidence': 0.5,
      });

      expect(entry.equipmentId, 'bench_press');
    });

    test('tolerates a missing confidence and a missing source', () {
      final entry = recognitionEntryFromFirestore('squat_rack', {
        'recognisedAt': t0.toIso8601String(),
      });

      expect(entry.confidence, 0);
      expect(entry.source, isNull);
    });

    test('does not mutate the caller\'s map', () {
      final stored = <String, dynamic>{
        'recognisedAt': Timestamp.fromDate(t0),
        'confidence': 0.5,
      };

      recognitionEntryFromFirestore('bench', stored);

      expect(stored['recognisedAt'], isA<Timestamp>());
      expect(stored.containsKey('equipmentId'), isFalse);
    });
  });

  group('recognitionEntryToFirestore', () {
    test('round-trips through the decoder unchanged', () {
      final entry = RecognitionEntry(
        equipmentId: 'lat_pulldown',
        recognisedAt: t0,
        confidence: 0.82,
        source: RecognitionSource.photo,
      );

      final stored = recognitionEntryToFirestore(entry);
      expect(recognitionEntryFromFirestore('lat_pulldown', stored), entry);
    });

    test('writes recognisedAt as a UTC ISO-8601 string so orderBy is correct',
        () {
      // Lexicographic order on these strings must match chronological order,
      // which is what the `orderBy('recognisedAt', descending: true)` query
      // relies on.
      final earlier = recognitionEntryToFirestore(RecognitionEntry(
        equipmentId: 'a',
        recognisedAt: DateTime(2026, 7, 29, 9),
        confidence: 0.5,
      ))['recognisedAt'] as String;
      final later = recognitionEntryToFirestore(RecognitionEntry(
        equipmentId: 'a',
        recognisedAt: DateTime(2026, 7, 29, 11),
        confidence: 0.5,
      ))['recognisedAt'] as String;

      expect(earlier.endsWith('Z'), isTrue);
      expect(later.endsWith('Z'), isTrue);
      expect(earlier.compareTo(later), lessThan(0));
    });
  });

  group('the Firestore write path folds through the shared rule', () {
    // `record()` merges the stored document with the incoming entry using
    // RecognitionDedup — the same call the in-memory repository makes. This
    // asserts on that composition directly, which is the part of the write
    // that carries the logic; the Firestore round-trip itself does not.
    test('a stored document plus a burst frame keeps one row, best confidence',
        () {
      final stored = recognitionEntryFromFirestore('bench', {
        'recognisedAt': Timestamp.fromDate(t0),
        'confidence': 0.9,
        'source': 'live',
      });
      final incoming = RecognitionEntry(
        equipmentId: 'bench',
        recognisedAt: t0.add(const Duration(minutes: 2)),
        confidence: 0.3,
        source: RecognitionSource.live,
      );

      final merged = RecognitionDedup.merge(stored, incoming);
      final written = recognitionEntryToFirestore(merged);

      expect(written['confidence'], 0.9);
      expect(
        written['recognisedAt'],
        t0.add(const Duration(minutes: 2)).toIso8601String(),
      );
    });

    test('a visit days later re-measures the confidence', () {
      final stored = recognitionEntryFromFirestore('bench', {
        'recognisedAt': Timestamp.fromDate(t0),
        'confidence': 0.9,
      });
      final incoming = RecognitionEntry(
        equipmentId: 'bench',
        recognisedAt: t0.add(const Duration(days: 3)),
        confidence: 0.3,
      );

      expect(RecognitionDedup.merge(stored, incoming).confidence, 0.3);
    });
  });
}
