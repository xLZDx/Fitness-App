/// Largest number of operations one Firestore batch may hold is 500; deletes
/// are issued in chunks of this size to stay clear of it.
const int kDeleteChunkSize = 400;

/// Repeatedly [fetch]es up to [chunkSize] items and hands them to [commit]
/// until the source is exhausted. Kept free of Firestore types so the chunking
/// rule itself is unit-testable; the Firestore repositories supply `fetch`
/// (a `limit(chunkSize).get()`) and `commit` (one batch of deletes).
///
/// A short chunk ends the loop without a further fetch; a full chunk is
/// followed by another fetch, so an exact multiple of [chunkSize] terminates on
/// an empty fetch. Returns the number of items passed to [commit].
Future<int> deleteInChunks<T>({
  required Future<List<T>> Function(int limit) fetch,
  required Future<void> Function(List<T> chunk) commit,
  int chunkSize = kDeleteChunkSize,
}) async {
  var total = 0;
  while (true) {
    final chunk = await fetch(chunkSize);
    if (chunk.isEmpty) break;
    await commit(chunk);
    total += chunk.length;
    if (chunk.length < chunkSize) break;
  }
  return total;
}
