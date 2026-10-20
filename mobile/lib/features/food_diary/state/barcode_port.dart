/// Port wrapping `mobile_scanner` (design s17.4): the barcode page talks to
/// [BarcodePort] only, so widget tests use [FakeBarcodePort] and never touch
/// the camera plugin.
///
/// No `formats` filter is passed: every symbology is decoded and the page keeps
/// only values that pass `GtinValidator` (EAN-8, EAN-13, UPC-A, UPC-E as its
/// 8-digit form, ITF-14). That avoids depending on enum names that differ
/// between mobile_scanner majors.
///
/// Android: the `dev.steenbakker.mobile_scanner.useUnbundled` manifest flag is
/// intentionally left at its default until the on-device VERIFY (Play-services
/// model download) is recorded.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

abstract class BarcodePort {
  /// Raw decoded values, one event per detection.
  Stream<String> get codes;

  /// The live camera preview. [onError] is built when the camera cannot start
  /// (permission denied, no camera).
  Widget buildPreview(BuildContext context, WidgetBuilder onError);

  Future<void> toggleTorch();

  /// Stops decoding (keeps the controller reusable).
  Future<void> pause();

  Future<void> resume();

  Future<void> dispose();
}

class MobileScannerBarcodePort implements BarcodePort {
  MobileScannerBarcodePort()
      : _controller = MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
        );

  final MobileScannerController _controller;
  final StreamController<String> _codes = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Widget buildPreview(BuildContext context, WidgetBuilder onError) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final v = b.rawValue;
          if (v != null && v.isNotEmpty && !_codes.isClosed) _codes.add(v);
        }
      },
      errorBuilder: (context, error, child) => onError(context),
    );
  }

  @override
  Future<void> toggleTorch() => _controller.toggleTorch();

  @override
  Future<void> pause() async {
    try {
      await _controller.stop();
    } catch (_) {
      // Not started yet: nothing to stop.
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _controller.start();
    } catch (_) {
      // Already running or the camera is unavailable; the preview shows it.
    }
  }

  @override
  Future<void> dispose() async {
    await _codes.close();
    await _controller.dispose();
  }
}

/// Test double: [emit] pushes a decoded value; [failed] makes the preview show
/// the error builder (camera unavailable).
class FakeBarcodePort implements BarcodePort {
  FakeBarcodePort({this.failed = false});

  final bool failed;
  final StreamController<String> _codes = StreamController<String>.broadcast();
  int pauses = 0;
  int resumes = 0;
  int torchToggles = 0;
  bool disposed = false;

  void emit(String value) => _codes.add(value);

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Widget buildPreview(BuildContext context, WidgetBuilder onError) =>
      failed ? onError(context) : const SizedBox.expand(key: Key('fake.preview'));

  @override
  Future<void> toggleTorch() async => torchToggles++;

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _codes.close();
  }
}

/// A NEW port per page; the page disposes it.
final barcodePortFactoryProvider =
    Provider<BarcodePort Function()>((_) => MobileScannerBarcodePort.new);
