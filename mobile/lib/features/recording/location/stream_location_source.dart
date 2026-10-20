import 'dart:async';

import 'fix.dart';
import 'location_source.dart';

/// Creates the platform position stream for one request/interval. The only
/// plugin-specific piece; tests supply a fake stream here.
typedef PositionStreamFactory = Stream<Fix> Function(
  LocationRequest request,
  int intervalSeconds,
);

/// Plugin-independent [LocationSource] logic: one outward stream, one counted
/// subscription, and serialized `setInterval` / `stop`.
///
/// - `stop` never awaits the outward controller's `close` (that future can wait
///   on the listener whose cancel invoked `stop`: deadlock, finding U1).
/// - `setInterval` and `stop` run through one in-flight chain so an overlapping
///   re-create can never leak a position stream past `stop` (finding U2).
class StreamLocationSource implements LocationSource {
  StreamLocationSource(this._factory);

  final PositionStreamFactory _factory;

  StreamController<Fix>? _out;
  StreamSubscription<Fix>? _inner;
  LocationRequest? _request;
  int _generation = 0;
  Future<void> _tail = Future<void>.value();

  @override
  int get activeSubscriptions => _out == null ? 0 : 1;

  @override
  Stream<void> get engineDetached => const Stream<void>.empty();

  @override
  Stream<Fix> start(LocationRequest request) {
    if (_out != null) throw StateError('LocationSource already started');
    _generation++;
    _request = request;
    final out = StreamController<Fix>(onCancel: () {
      unawaited(stop());
    });
    _out = out;
    _attach(request.intervalSeconds);
    return out.stream;
  }

  void _attach(int intervalSeconds) {
    final out = _out;
    final request = _request;
    if (out == null || request == null) return;
    try {
      _inner = _factory(request, intervalSeconds).listen(
        (f) {
          if (!out.isClosed) out.add(f);
        },
        onError: (Object e, StackTrace s) {
          if (!out.isClosed) out.addError(e, s);
        },
      );
    } catch (e, s) {
      if (!out.isClosed) out.addError(e, s);
    }
  }

  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> setInterval(int seconds) {
    if (_out == null) return Future<void>.value();
    final gen = _generation;
    return _serial(() async {
      if (_out == null || gen != _generation) return;
      final old = _inner;
      _inner = null;
      await old?.cancel();
      if (_out == null || gen != _generation) return;
      _attach(seconds);
    });
  }

  @override
  Future<void> stop() {
    final out = _out;
    final inner = _inner;
    _out = null;
    _inner = null;
    _request = null;
    _generation++;
    return _serial(() async {
      await inner?.cancel();
      if (out != null && !out.isClosed) {
        // Deliberately not awaited: see class docs (U1).
        unawaited(out.close());
      }
    });
  }
}
