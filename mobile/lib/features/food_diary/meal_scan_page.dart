import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/privacy/data_notice.dart';
import '../nutrition_plan/state/weight_providers.dart';
import 'data/check_these.dart';
import 'data/food_entry.dart';
import 'data/portion_math.dart';
import 'food_detail_sheet.dart';
import 'state/capture_image_port.dart';
import 'state/diary_providers.dart';
import 'state/food_api.dart';
import 'state/image_prep.dart';
import 'state/meal_thumbnail_store.dart';
import 'widgets/scan_common.dart';

/// Local switch key for the optional private thumbnail (default ON).
const String kMealThumbnailPref = 'food_diary.meal_thumbnail.enabled';

/// `/nutrition/add/photo?day=&slot=`: photograph a meal (design s17.2, s17.3).
/// The photo is resized to a 1024 px long edge on the device, sent inline to
/// `analyzeMealPhoto` and discarded; nothing is uploaded for retention. An
/// optional note ("this is oat milk") is authoritative on the server. The user
/// ALWAYS confirms in the detail sheet; nothing is logged without Save. An
/// optional encrypted thumbnail stays on this phone and is deleted with the
/// entry.
class MealScanPage extends ConsumerStatefulWidget {
  const MealScanPage({super.key, this.day, this.slot});

  final String? day;
  final MealSlot? slot;

  @override
  ConsumerState<MealScanPage> createState() => _MealScanPageState();
}

class _MealScanPageState extends ConsumerState<MealScanPage> {
  final _note = TextEditingController();
  Uint8List? _prepared;
  bool _picking = false;
  bool _working = false;
  bool _keepThumb = true;
  String? _message;
  bool _notAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadThumbPref();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadThumbPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(kMealThumbnailPref);
      if (v != null && mounted) setState(() => _keepThumb = v);
    } catch (_) {
      // Default (on) stays.
    }
  }

  Future<void> _setThumbPref(bool v) async {
    setState(() => _keepThumb = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kMealThumbnailPref, v);
    } catch (_) {
      // Session-only switch is acceptable.
    }
  }

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
        await prepareJpegInBackground(raw, longEdge: kMealLongEdge);
    if (!mounted) return;
    setState(() {
      _picking = false;
      _prepared = prepared;
      if (prepared == null) _message = l10n.foodMealImageInvalid;
    });
  }

  Future<void> _analyse() async {
    final bytes = _prepared;
    if (bytes == null || _working) return;
    final l10n = AppLocalizations.of(context);
    // D-79: the notice comes BEFORE the first food-AI call.
    if (!await ensureDataNoticeAcknowledged(context, ref)) return;
    if (!mounted) return;
    final lang = scanLanguageCode(context);
    setState(() {
      _working = true;
      _message = null;
      _notAvailable = false;
    });
    try {
      final meal = await ref.read(foodApiProvider).analyzeMeal(
            imageBase64: base64Encode(bytes),
            mimeType: 'image/jpeg',
            note: _note.text.trim(),
            languageCode: lang,
          );
      if (!mounted) return;
      final items = [
        for (final i in meal.items)
          if (i.toFoodItem() case final f?) f,
      ];
      if (items.isEmpty) {
        setState(() {
          _working = false;
          _message = l10n.foodMealNoFood;
        });
        return;
      }
      final codes = <CheckCode>[
        for (final i in meal.items) ...i.checkCodes,
        ...meal.assumptions,
        if (items.length < meal.items.length) CheckCode.foodNotMatched,
      ];
      final now = ref.read(nutritionClockProvider)();
      final entry = buildEntry(
        id: newEntryId(now),
        day: resolveScanDay(ref, widget.day),
        slot: widget.slot ?? defaultSlotFor(now),
        loggedAt: now,
        name: meal.mealName.length > FoodEntry.maxNameLength
            ? meal.mealName.substring(0, FoodEntry.maxNameLength)
            : meal.mealName,
        source: EntrySource.photo,
        confidence: meal.confidence,
        items: items,
        checkThese: CheckThese.fromCodes(codes),
        model: meal.model,
      );
      setState(() => _working = false);
      final saved = await showFoodDetailSheet(context, entry);
      if (!saved) return;
      if (_keepThumb) await _storeThumbnail(entry.id, bytes);
      if (mounted) context.go('/nutrition/diary');
    } on FoodApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _notAvailable = e.isNotAvailableYet;
        _message = scanFailureMessage(l10n, e, generic: l10n.foodMealFailed);
      });
    }
  }

  /// Best effort: a failed thumbnail never loses the saved entry.
  Future<void> _storeThumbnail(String entryId, Uint8List prepared) async {
    try {
      final thumb =
          await prepareJpegInBackground(prepared, longEdge: kMealThumbLongEdge);
      if (thumb == null) return;
      final store = await ref.read(mealThumbnailStoreProvider.future);
      await store?.put(entryId, thumb);
    } catch (_) {
      // No thumbnail; the entry itself is already saved.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prepared = _prepared;
    final busy = _picking || _working;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(l10n.foodMealScanTitle)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.foodMealScanIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (prepared != null) ...[
              Semantics(
                image: true,
                label: l10n.foodMealPreviewLabel,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(prepared,
                      key: const Key('meal.preview'),
                      height: 240,
                      fit: BoxFit.cover,
                      gaplessPlayback: true),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('meal.note'),
                controller: _note,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(hintText: l10n.foodMealNoteHint),
              ),
              SwitchListTile(
                key: const Key('meal.thumb'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.foodMealThumbSwitch),
                subtitle: Text(l10n.foodMealThumbHint),
                value: _keepThumb,
                onChanged: busy ? null : _setThumbPref,
              ),
              if (_message != null)
                Semantics(
                  liveRegion: true,
                  child: Text(_message!,
                      key: Key(_notAvailable ? 'meal.off' : 'meal.msg')),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('meal.analyse'),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: busy || _notAvailable ? null : _analyse,
                child: _working
                    ? Semantics(
                        label: l10n.foodMealAnalysing,
                        child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Text(l10n.foodMealAnalyse),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('meal.change'),
                style:
                    TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: busy ? null : () => setState(() => _prepared = null),
                child: Text(l10n.foodMealChange),
              ),
            ] else ...[
              if (_message != null)
                Semantics(
                  liveRegion: true,
                  child: Text(_message!, key: const Key('meal.msg')),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('meal.take'),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: busy ? null : () => _pick(CaptureSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.foodMealTake),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('meal.pick'),
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
