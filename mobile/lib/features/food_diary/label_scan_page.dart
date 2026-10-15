import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/privacy/data_notice.dart';
import '../nutrition_plan/state/weight_providers.dart';
import 'data/check_these.dart';
import 'data/food_entry.dart';
import 'data/food_source.dart';
import 'data/label_scale.dart';
import 'data/portion_math.dart';
import 'food_detail_sheet.dart';
import 'state/capture_image_port.dart';
import 'state/diary_repository.dart';
import 'state/diary_providers.dart';
import 'state/food_api.dart';
import 'state/image_prep.dart';
import 'widgets/scan_common.dart';

/// The values the user confirmed on the label sheet.
class LabelDraft {
  const LabelDraft({required this.name, required this.per100g, this.servingG});

  final String name;
  final Per100g per100g;
  final double? servingG;
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Validates the confirmation fields; null when anything is missing or outside
/// 0..1000 (the rules bound). Serving is optional but must be positive when
/// typed. Pure, exposed for tests.
LabelDraft? parseLabelDraft({
  required String name,
  required String kcal,
  required String protein,
  required String carbs,
  required String fat,
  String serving = '',
}) {
  final n = name.trim();
  final k = _num(kcal);
  final p = _num(protein);
  final c = _num(carbs);
  final f = _num(fat);
  if (n.isEmpty || n.length > SavedFood.maxNameLength) return null;
  if (k == null || p == null || c == null || f == null) return null;
  for (final v in [k, p, c, f]) {
    if (!v.isFinite || v < 0 || v > 1000) return null;
  }
  double? s;
  if (serving.trim().isNotEmpty) {
    s = _num(serving);
    if (s == null || !s.isFinite || s <= 0 || s > 100000) return null;
  }
  return LabelDraft(
    name: n,
    per100g: Per100g(kcal: k, proteinG: p, carbsG: c, fatG: f),
    servingG: s,
  );
}

/// `/nutrition/add/label?day=&slot=`: photograph a nutrition table (design
/// s17.6). The image is resized to a 1280 px long edge, read on the server
/// (Cyrillic-capable) and the result is ALWAYS shown in an editable
/// confirmation sheet; a `saved_food` is written only after Confirm and nothing
/// is logged until Save in the detail sheet.
class LabelScanPage extends ConsumerStatefulWidget {
  const LabelScanPage({super.key, this.day, this.slot});

  final String? day;
  final MealSlot? slot;

  @override
  ConsumerState<LabelScanPage> createState() => _LabelScanPageState();
}

class _LabelScanPageState extends ConsumerState<LabelScanPage> {
  Uint8List? _prepared;
  bool _picking = false;
  bool _working = false;
  bool _notAvailable = false;
  String? _message;

  Future<void> _pick(CaptureSource source) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _picking = true;
      _message = null;
      _notAvailable = false;
    });
    final raw = await ref.read(captureImagePortProvider).pick(source);
    if (!mounted) return;
    if (raw == null) {
      setState(() => _picking = false);
      return;
    }
    final prepared =
        await prepareJpegInBackground(raw, longEdge: kLabelLongEdge);
    if (!mounted) return;
    setState(() {
      _picking = false;
      _prepared = prepared;
      if (prepared == null) _message = l10n.foodMealImageInvalid;
    });
  }

  Future<void> _read() async {
    final bytes = _prepared;
    if (bytes == null || _working) return;
    final l10n = AppLocalizations.of(context);
    if (!await ensureDataNoticeAcknowledged(context, ref)) return;
    if (!mounted) return;
    final lang = scanLanguageCode(context);
    setState(() {
      _working = true;
      _message = null;
      _notAvailable = false;
    });
    LabelReading reading;
    try {
      reading = await ref.read(foodApiProvider).parseLabel(
            imageBase64: base64Encode(bytes),
            mimeType: 'image/jpeg',
            languageCode: lang,
          );
    } on FoodApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _notAvailable = e.isNotAvailableYet;
        _message = scanFailureMessage(l10n, e, generic: l10n.foodLabelFailed);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _working = false);

    // Prefer per-100 g; else convert per-serving values when the serving
    // weight is known (never divide by an unusable weight).
    var converted = false;
    Per100g? initial = reading.per100g;
    if (initial == null && reading.perServing != null) {
      final r = LabelScale.toPer100g(reading.perServing!, reading.servingG);
      initial = r.values;
      converted = r.isOk;
    }
    final draft = await showModalBottomSheet<LabelDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LabelConfirmSheet(
        initial: initial,
        servingG: reading.servingG,
        converted: converted,
        unreadable: initial == null,
        needsCheck: reading.checkCodes.contains(CheckCode.labelAmbiguous),
      ),
    );
    if (draft == null || !mounted) return;
    await _saveAndLog(draft, reading.checkCodes);
  }

  Future<void> _saveAndLog(LabelDraft draft, List<CheckCode> readCodes) async {
    final l10n = AppLocalizations.of(context);
    if (!await ensureDataNoticeAcknowledged(context, ref)) return;
    if (!mounted) return;
    final now = ref.read(nutritionClockProvider)();
    final id = newEntryId(now);
    // The user confirmed the numbers: only now is a saved food written.
    final status = await ref.read(foodDiaryActionsProvider).saveFood(SavedFood(
          id: 'l$id',
          name: draft.name,
          per100g: draft.per100g,
          servingG: draft.servingG,
        ));
    if (!mounted) return;
    if (status != DiaryWriteStatus.saved) {
      setState(() => _message = l10n.foodDiaryWriteFailed);
      return;
    }
    final name = draft.name.length > FoodItem.maxNameLength
        ? draft.name.substring(0, FoodItem.maxNameLength)
        : draft.name;
    final codes = <CheckCode>[
      ...readCodes,
      if (!isAtwaterConsistent(draft.per100g)) CheckCode.dataInconsistent,
      if (draft.servingG == null) CheckCode.scaleMissing,
    ];
    final entry = buildEntry(
      id: id,
      day: resolveScanDay(ref, widget.day),
      slot: widget.slot ?? defaultSlotFor(now),
      loggedAt: now,
      name: name,
      source: EntrySource.label,
      confidence: EntryConfidence.medium,
      items: [
        FoodItem(
          foodRef: 'label',
          name: name,
          grams: MacroRange.exact(draft.servingG ?? quickLogGrams),
          per100g: draft.per100g,
          matchQuality: MatchQuality.exact,
          source: FoodSource.label,
        ),
      ],
      checkThese: CheckThese.fromCodes(codes),
    );
    final saved = await showFoodDetailSheet(context, entry);
    if (saved && mounted) context.go('/nutrition/diary');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prepared = _prepared;
    final busy = _picking || _working;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(l10n.foodLabelTitle)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.foodLabelIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (prepared != null) ...[
              Semantics(
                image: true,
                label: l10n.foodMealPreviewLabel,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(prepared,
                      key: const Key('label.preview'),
                      height: 240,
                      fit: BoxFit.cover,
                      gaplessPlayback: true),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: Text(_message!,
                    key: Key(_notAvailable ? 'label.off' : 'label.msg')),
              ),
            const SizedBox(height: 8),
            if (prepared != null) ...[
              FilledButton(
                key: const Key('label.read'),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: busy || _notAvailable ? null : _read,
                child: _working
                    ? Semantics(
                        label: l10n.foodLabelReading,
                        child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Text(l10n.foodLabelRead),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('label.change'),
                style:
                    TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: busy ? null : () => setState(() => _prepared = null),
                child: Text(l10n.foodMealChange),
              ),
            ] else ...[
              FilledButton.icon(
                key: const Key('label.take'),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: busy ? null : () => _pick(CaptureSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.foodMealTake),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('label.pick'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54)),
                onPressed: busy ? null : () => _pick(CaptureSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.foodMealPick),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The ALWAYS-shown editable confirmation sheet. Pops a [LabelDraft] on
/// Confirm, null on Cancel / dismiss.
class LabelConfirmSheet extends StatefulWidget {
  const LabelConfirmSheet({
    super.key,
    required this.initial,
    this.servingG,
    this.converted = false,
    this.unreadable = false,
    this.needsCheck = false,
  });

  final Per100g? initial;
  final double? servingG;
  final bool converted;
  final bool unreadable;
  final bool needsCheck;

  @override
  State<LabelConfirmSheet> createState() => _LabelConfirmSheetState();
}

class _LabelConfirmSheetState extends State<LabelConfirmSheet> {
  late final _name = TextEditingController();
  late final _serving = TextEditingController(text: _fmt(widget.servingG));
  late final _kcal = TextEditingController(text: _fmt(widget.initial?.kcal));
  late final _p = TextEditingController(text: _fmt(widget.initial?.proteinG));
  late final _c = TextEditingController(text: _fmt(widget.initial?.carbsG));
  late final _f = TextEditingController(text: _fmt(widget.initial?.fatG));
  bool _invalid = false;

  static String _fmt(double? v) {
    if (v == null) return '';
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  @override
  void dispose() {
    for (final c in [_name, _serving, _kcal, _p, _c, _f]) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final draft = parseLabelDraft(
      name: _name.text,
      kcal: _kcal.text,
      protein: _p.text,
      carbs: _c.text,
      fat: _f.text,
      serving: _serving.text,
    );
    if (draft == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget field(String key, TextEditingController c, String label,
            {bool number = true}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            key: Key(key),
            controller: c,
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(labelText: label),
          ),
        );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.foodLabelConfirmTitle,
                style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 4),
          Text(l10n.foodLabelConfirmHint, style: theme.textTheme.bodySmall),
          if (widget.unreadable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.foodLabelNothing,
                  key: const Key('labelSheet.unreadable')),
            ),
          if (widget.converted)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.foodLabelConverted,
                  key: const Key('labelSheet.converted')),
            ),
          if (widget.needsCheck)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.foodCheckHelpLabelAmbiguous,
                  key: const Key('labelSheet.ambiguous')),
            ),
          const SizedBox(height: 12),
          field('labelSheet.name', _name, l10n.foodLabelName, number: false),
          field('labelSheet.serving', _serving, l10n.foodLabelServing),
          field('labelSheet.kcal', _kcal, l10n.foodQuickKcal),
          field('labelSheet.protein', _p, l10n.foodQuickProtein),
          field('labelSheet.carbs', _c, l10n.foodQuickCarbs),
          field('labelSheet.fat', _f, l10n.foodQuickFat),
          if (_invalid)
            Semantics(
              liveRegion: true,
              child: Text(l10n.foodLabelInvalid,
                  key: const Key('labelSheet.invalid')),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('labelSheet.confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _confirm,
            child: Text(l10n.foodLabelConfirm),
          ),
          TextButton(
            key: const Key('labelSheet.cancel'),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.foodScanCancel),
          ),
        ],
      ),
    );
  }
}
