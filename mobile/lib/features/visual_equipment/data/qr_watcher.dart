import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlkit;
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;

import '../../../core/camera/camera_session.dart';
import '../../equipment/data/equipment_models.dart' show ScanResult;

/// Watches the camera for our own equipment stickers.
///
/// Replaces `mobile_scanner`, which brought a second camera stack: it owned the
/// device whenever live mode was off, and handing over meant stopping one
/// controller, sleeping 250ms, and hoping. One session now feeds both this and
/// the equipment labeler.
///
/// Deliberately restricted to QR. `mobile_scanner` accepted every format by
/// default; narrowing to the one format our stickers use means fewer things the
/// native decoder has to try per frame, and the payload check below is what
/// actually decides anyway.
///
/// Errors are reported on [results] rather than swallowed. This runs whenever
/// the Scan tab is open, so a dead decoder here means QR silently never works —
/// exactly the kind of failure that reaches a phone unnoticed.
class QrWatcher {
  QrWatcher({required this.session});

  final CameraSession session;

  mlkit.BarcodeScanner? _scanner;
  StreamSubscription<InputImage>? _sub;
  final StreamController<ScanResult> _ctrl =
      StreamController<ScanResult>.broadcast();

  /// Guards against re-entrancy: decoding is slower than the frame rate.
  bool _busy = false;
  bool _running = false;

  /// Payloads that parsed as ours. Foreign codes never reach here.
  Stream<ScanResult> results() => _ctrl.stream;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _scanner = mlkit.BarcodeScanner(formats: [mlkit.BarcodeFormat.qrCode]);
    await session.start();
    _running = true;
    _sub = session.frames().listen(
          _onFrame,
          // A session-level failure (the stream stalling, say) is not this
          // watcher's to report twice; the session already surfaces it to
          // whoever else is attached. Logged so it is diagnosable.
          onError: (Object e) => debugPrint('qr watcher upstream error: $e'),
        );
  }

  Future<void> _onFrame(InputImage input) async {
    if (_busy || !_running) return;
    _busy = true;
    try {
      final codes = await _scanner!.processImage(input);
      for (final code in codes) {
        final parsed = ScanResult.tryParse(code.rawValue);
        // Not ours: keep watching quietly. A gym is full of other barcodes.
        if (parsed == null) continue;
        if (!_ctrl.isClosed) _ctrl.add(parsed);
        break;
      }
    } on PlatformException catch (e) {
      debugPrint('barcode scanning failed natively: ${e.code} ${e.message}');
      if (!_ctrl.isClosed) {
        _ctrl.addError(StateError(
          'QR scanning failed: ${e.message ?? e.code}',
        ));
      }
      unawaited(stop());
    } catch (e) {
      debugPrint('qr frame dropped: $e');
    } finally {
      _busy = false;
    }
  }

  /// Detaches the decoder. Leaves the session alone — the preview needs it.
  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _scanner?.close();
    } catch (e) {
      debugPrint('barcode scanner close: $e');
    }
    _scanner = null;
  }

  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
  }
}
