import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../nutrition_plan/state/weight_providers.dart';
import 'data/food_entry.dart';
import 'data/gtin_validator.dart';
import 'data/portion_math.dart';
import 'food_detail_sheet.dart';
import 'state/barcode_port.dart';
import 'state/diary_providers.dart';
import 'state/food_api.dart';
import 'widgets/scan_common.dart';

enum _Phase { scanning, looking, notFound, failed }

/// `/nutrition/add/barcode?day=&slot=`: scan a product barcode (design s17.4).
/// Only GTIN-valid values (EAN-8/13, UPC-A/E, ITF-14) reach the server; the
/// lookup result always ends in the same confirm sheet, nothing is logged
/// without Save. A not-found product offers the label scan or quick log; a
/// typed barcode covers a denied camera.
class BarcodeScanPage extends ConsumerStatefulWidget {
  const BarcodeScanPage({super.key, this.day, this.slot});

  final String? day;
  final MealSlot? slot;

  @override
  ConsumerState<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends ConsumerState<BarcodeScanPage> {
  late final BarcodePort _port = ref.read(barcodePortFactoryProvider)();
  StreamSubscription<String>? _sub;
  final _manual = TextEditingController();
  _Phase _phase = _Phase.scanning;
  String? _message;
  bool _invalidSeen = false;

  @override
  void initState() {
    super.initState();
    _sub = _port.codes.listen(_onCode);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _manual.dispose();
    _port.dispose();
    super.dispose();
  }

  String get _query =>
      '?day=${widget.day ?? ''}&slot=${(widget.slot ?? MealSlot.snack).name}';

  void _onCode(String raw) {
    if (_phase != _Phase.scanning) return;
    final code = GtinValidator.normaliseValid(raw);
    if (code == null) {
      if (!_invalidSeen && mounted) setState(() => _invalidSeen = true);
      return;
    }
    _lookup(code);
  }

  void _submitManual() {
    final code = GtinValidator.normaliseValid(_manual.text);
    if (code == null) {
      setState(() => _invalidSeen = true);
      return;
    }
    _lookup(code);
  }

  Future<void> _lookup(String code) async {
    if (_phase == _Phase.looking) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _phase = _Phase.looking;
      _invalidSeen = false;
      _message = null;
    });
    await _port.pause();
    try {
      final result = await ref.read(foodApiProvider).lookupBarcode(code);
      if (!mounted) return;
      final cand = result.candidate;
      if (cand == null) {
        setState(() => _phase = _Phase.notFound);
        return;
      }
      final now = ref.read(nutritionClockProvider)();
      final name = cand.name.length > FoodItem.maxNameLength
          ? cand.name.substring(0, FoodItem.maxNameLength)
          : cand.name;
      final entry = buildEntry(
        id: newEntryId(now),
        day: resolveScanDay(ref, widget.day),
        slot: widget.slot ?? defaultSlotFor(now),
        loggedAt: now,
        name: name,
        source: EntrySource.barcode,
        confidence:
            cand.complete ? EntryConfidence.high : EntryConfidence.medium,
        items: [
          FoodItem(
            foodRef: cand.foodRef,
            name: name,
            grams: MacroRange.exact(cand.servingG ?? quickLogGrams),
            per100g: cand.per100g,
            matchQuality: MatchQuality.exact,
            source: cand.source,
          ),
        ],
      );
      setState(() => _phase = _Phase.scanning);
      final saved = await showFoodDetailSheet(context, entry);
      if (!mounted) return;
      if (saved) {
        context.go('/nutrition/diary');
      } else {
        await _port.resume();
      }
    } on FoodApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _message = scanFailureMessage(l10n, e, generic: l10n.foodBarcodeFailed);
      });
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _phase = _Phase.scanning;
      _message = null;
      _invalidSeen = false;
    });
    await _port.resume();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget cameraError(BuildContext c) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              liveRegion: true,
              child: Text(l10n.foodBarcodeCameraError,
                  key: const Key('barcode.cameraError'),
                  textAlign: TextAlign.center),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(l10n.foodBarcodeTitle)),
        actions: [
          IconButton(
            key: const Key('barcode.torch'),
            tooltip: l10n.foodBarcodeTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _port.toggleTorch,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 280,
              width: double.infinity,
              child: ClipRect(child: _port.buildPreview(context, cameraError)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(l10n.foodBarcodeHint, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  if (_phase == _Phase.looking)
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        key: const Key('barcode.looking'),
                        children: [
                          const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Text(l10n.foodBarcodeLooking),
                        ],
                      ),
                    ),
                  if (_invalidSeen && _phase == _Phase.scanning)
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.foodBarcodeInvalid,
                          key: const Key('barcode.invalid')),
                    ),
                  if (_phase == _Phase.failed && _message != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(_message!, key: const Key('barcode.failed')),
                    ),
                  if (_phase == _Phase.notFound) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(l10n.foodBarcodeNotFound,
                          key: const Key('barcode.notFound')),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('barcode.toLabel'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54)),
                      onPressed: () =>
                          context.pushReplacement('/nutrition/add/label$_query'),
                      child: Text(l10n.foodAddLabel),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('barcode.toQuick'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      onPressed: () =>
                          context.pushReplacement('/nutrition/add$_query'),
                      child: Text(l10n.foodAddQuickLog),
                    ),
                  ],
                  if (_phase == _Phase.notFound || _phase == _Phase.failed) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('barcode.again'),
                      style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      onPressed: _scanAgain,
                      child: Text(l10n.foodBarcodeScanAgain),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('barcode.manual'),
                    controller: _manual,
                    keyboardType: TextInputType.number,
                    maxLength: 14,
                    decoration:
                        InputDecoration(labelText: l10n.foodBarcodeManualField),
                    onSubmitted: (_) => _submitManual(),
                  ),
                  OutlinedButton(
                    key: const Key('barcode.manualGo'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _phase == _Phase.looking ? null : _submitManual,
                    child: Text(l10n.foodBarcodeManualGo),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
