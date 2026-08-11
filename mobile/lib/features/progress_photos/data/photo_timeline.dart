import 'progress_photo.dart';

/// One month's worth of photos, newest month first, newest photo first
/// inside the month.
class PhotoMonth {
  const PhotoMonth({required this.month, required this.photos});

  /// First day of the month, local time. Only year+month are meaningful.
  final DateTime month;
  final List<ProgressPhoto> photos;

  int get count => photos.length;
}

/// Groups photos into months for the timeline.
///
/// Sorting is done here rather than left to the caller because two callers
/// already exist (the timeline list and the compare picker) and a list that
/// is "usually sorted because the repository happened to append in order" is
/// the kind of thing that breaks the day a photo is imported with a backdated
/// [ProgressPhoto.takenAt].
List<PhotoMonth> groupByMonth(List<ProgressPhoto> photos) {
  if (photos.isEmpty) return const [];
  final buckets = <String, List<ProgressPhoto>>{};
  for (final p in photos) {
    final key = '${p.takenAt.year}-${p.takenAt.month}';
    (buckets[key] ??= []).add(p);
  }
  final months = <PhotoMonth>[];
  for (final entry in buckets.entries) {
    final list = [...entry.value]
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final first = list.first.takenAt;
    months.add(PhotoMonth(
      month: DateTime(first.year, first.month),
      photos: List.unmodifiable(list),
    ));
  }
  months.sort((a, b) => b.month.compareTo(a.month));
  return List.unmodifiable(months);
}

/// How many photos [months] holds in total.
int totalPhotos(List<PhotoMonth> months) =>
    months.fold(0, (sum, m) => sum + m.count);

/// The [count] newest photos, still grouped by month.
///
/// The timeline pages on this rather than rendering the whole history, because
/// every tile that mounts decrypts a blob and holds a decoded bitmap: the cost
/// of the grid was linear in how long the user had been using the feature, and
/// it was all paid at once when the screen opened.
///
/// Paging by PHOTO and not by MONTH is deliberate. Months are whatever size
/// the user's habits made them -- someone who shot daily for a month would get
/// thirty tiles from "one month", which is the same unbounded page with an
/// extra step.
///
/// Correctness here rests on [groupByMonth]'s ordering: newest month first,
/// newest photo first inside it. That makes any prefix of the flattened list
/// exactly "the N most recent photos", so a truncated month is truncated at
/// its oldest end.
List<PhotoMonth> newestMonths(List<PhotoMonth> months, int count) {
  if (count <= 0) return const [];
  final out = <PhotoMonth>[];
  var left = count;
  for (final m in months) {
    if (left <= 0) break;
    if (m.count <= left) {
      out.add(m);
      left -= m.count;
    } else {
      out.add(PhotoMonth(
        month: m.month,
        photos: List.unmodifiable(m.photos.take(left)),
      ));
      left = 0;
    }
  }
  return List.unmodifiable(out);
}

/// A pair chosen for the before/after view, oldest first.
class ComparePair {
  const ComparePair(this.before, this.after);

  final ProgressPhoto before;
  final ProgressPhoto after;

  /// Whole calendar days between the two shots.
  ///
  /// Counted on the dates, not on elapsed time. `difference().inDays` is off by
  /// one across a daylight-saving boundary — the clock jump makes the interval
  /// 23 hours short of a whole day, and Jan 1 to May 31 came back as 149 in
  /// Europe/Chisinau. A user reading "149 days" for exactly five months would
  /// be reading a bug.
  ///
  /// Never negative: [defaultComparePair] guarantees the order.
  int get daySpan {
    final a = DateTime.utc(
        before.takenAt.year, before.takenAt.month, before.takenAt.day);
    final b =
        DateTime.utc(after.takenAt.year, after.takenAt.month, after.takenAt.day);
    return b.difference(a).inDays;
  }
}

/// Picks the default before/after pair: the oldest and newest photos that
/// share an angle.
///
/// Angle matters more than recency here. A front-facing "before" against a
/// side-facing "after" is not a comparison, it is two unrelated pictures, and
/// a user reading it as progress would be reading noise. When no angle has two
/// or more photos the function returns null rather than pairing across angles
/// — an honest empty state beats a misleading pair.
///
/// Ties on angle are broken by span: the widest interval wins, because that is
/// the comparison the feature exists to show.
ComparePair? defaultComparePair(List<ProgressPhoto> photos) {
  if (photos.length < 2) return null;
  final byAngle = <ProgressPhotoAngle, List<ProgressPhoto>>{};
  for (final p in photos) {
    (byAngle[p.angle] ??= []).add(p);
  }
  ComparePair? best;
  for (final list in byAngle.values) {
    if (list.length < 2) continue;
    final sorted = [...list]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final pair = ComparePair(sorted.first, sorted.last);
    if (best == null || pair.daySpan > best.daySpan) best = pair;
  }
  return best;
}

/// Every photo sharing [angle], oldest first — the pool the compare picker
/// offers once the user overrides the default pair.
List<ProgressPhoto> photosForAngle(
  List<ProgressPhoto> photos,
  ProgressPhotoAngle angle,
) {
  final out = photos.where((p) => p.angle == angle).toList()
    ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  return List.unmodifiable(out);
}
