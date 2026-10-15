import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/body_scan_flags.dart';
import '../../core/privacy/data_notice.dart';
import '../nutrition_plan/state/weight_providers.dart';
import 'data/check_these.dart';
import 'data/food_entry.dart';
import 'data/portion_math.dart';
import 'food_detail_sheet.dart';
import 'state/diary_providers.dart';
import 'state/food_api.dart';

/// `/nutrition/add?day=yyyy-MM-dd&slot=lunch`: the ways to add food. Tiles
/// whose feature flag is off are HIDDEN (design C23): photo, describe and label
/// need `foodAi`; barcode needs `foodLookup`. Search, quick log and saved foods
/// always work.
class AddFoodPage extends ConsumerWidget {
  const AddFoodPage({super.key, this.day, this.slot});

  final String? day;
  final MealSlot? slot;

  String get _query => '?day=${day ?? ''}&slot=${(slot ?? MealSlot.snack).name}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final flags = ref.watch(bodyScanFlagsProvider);
    Widget tile(String key, IconData icon, String label, VoidCallback onTap) =>
        ListTile(
          key: Key(key),
          minTileHeight: 56,
          leading: Icon(icon),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(l10n.foodAddTitle)),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            tile('add.search', Icons.search, l10n.foodAddSearch,
                () => context.push('/nutrition/add/search$_query')),
            if (flags.foodAi)
              tile('add.describe', Icons.edit_note, l10n.foodAddDescribe, () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _DescribeSheet(day: day, slot: slot),
                ).then((_) {});
              }),
            if (flags.foodAi)
              tile('add.photo', Icons.photo_camera_outlined, l10n.foodAddPhoto,
                  () => context.push('/nutrition/scan/meal$_query')),
            if (flags.foodLookup)
              tile('add.barcode', Icons.qr_code_scanner, l10n.foodAddBarcode,
                  () => context.push('/nutrition/scan/barcode$_query')),
            if (flags.foodAi)
              tile('add.label', Icons.receipt_long_outlined, l10n.foodAddLabel,
                  () => context.push('/nutrition/scan/label$_query')),
            tile('add.quick', Icons.bolt, l10n.foodAddQuickLog, () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _QuickLogSheet(day: day, slot: slot),
              );
            }),
            tile('add.saved', Icons.bookmark_border, l10n.foodAddSaved,
                () => context.push('/nutrition/add/search$_query&saved=1')),
          ],
        ),
      ),
    );
  }
}

String _resolveDay(WidgetRef ref, String? day) =>
    (day != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day))
        ? day
        : dayKeyOf(ref.read(nutritionClockProvider)());

class _QuickLogSheet extends ConsumerStatefulWidget {
  const _QuickLogSheet({this.day, this.slot});
  final String? day;
  final MealSlot? slot;

  @override
  ConsumerState<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends ConsumerState<_QuickLogSheet> {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _p = TextEditingController();
  final _c = TextEditingController();
  final _f = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    for (final c in [_name, _kcal, _p, _c, _f]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _n(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _go() async {
    final kcal = _n(_kcal);
    final name = _name.text.trim();
    if (name.isEmpty || kcal == null || kcal < 0 || kcal > 1000) {
      setState(() => _invalid = true);
      return;
    }
    final now = ref.read(nutritionClockProvider)();
    final entry = quickLogEntry(
      id: newEntryId(now),
      day: _resolveDay(ref, widget.day),
      slot: widget.slot ?? defaultSlotFor(now),
      loggedAt: now,
      name: name.length > FoodItem.maxNameLength
          ? name.substring(0, FoodItem.maxNameLength)
          : name,
      kcal: kcal,
      proteinG: _n(_p) ?? 0,
      carbsG: _n(_c) ?? 0,
      fatG: _n(_f) ?? 0,
    );
    final saved = await showFoodDetailSheet(context, entry);
    if (saved && mounted) {
      Navigator.of(context).pop();
      context.go('/nutrition/diary');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            child: Text(l10n.foodQuickTitle,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          field('quick.name', _name, l10n.foodQuickName, number: false),
          field('quick.kcal', _kcal, l10n.foodQuickKcal),
          field('quick.protein', _p, l10n.foodQuickProtein),
          field('quick.carbs', _c, l10n.foodQuickCarbs),
          field('quick.fat', _f, l10n.foodQuickFat),
          if (_invalid)
            Semantics(liveRegion: true, child: Text(l10n.foodQuickInvalid)),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('quick.add'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _go,
            child: Text(l10n.foodQuickAdd),
          ),
        ],
      ),
    );
  }
}

class _DescribeSheet extends ConsumerStatefulWidget {
  const _DescribeSheet({this.day, this.slot});
  final String? day;
  final MealSlot? slot;

  @override
  ConsumerState<_DescribeSheet> createState() => _DescribeSheetState();
}

class _DescribeSheetState extends ConsumerState<_DescribeSheet> {
  final _text = TextEditingController();
  bool _working = false;
  String? _message;
  bool _notAvailable = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final l10n = AppLocalizations.of(context);
    final text = _text.text.trim();
    if (text.length < 3) return;
    // D-79: the notice comes BEFORE the first food-AI call.
    if (!await ensureDataNoticeAcknowledged(context, ref)) return;
    if (!mounted) return;
    final lang = Localizations.localeOf(context).languageCode == 'ru' ? 'ru' : 'en';
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final meal = await ref
          .read(foodApiProvider)
          .analyzeMeal(text: text, languageCode: lang);
      if (!mounted) return;
      final items = [
        for (final i in meal.items)
          if (i.toFoodItem() case final f?) f,
      ];
      if (items.isEmpty) {
        setState(() {
          _working = false;
          _message = l10n.foodDescribeNothing;
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
        day: _resolveDay(ref, widget.day),
        slot: widget.slot ?? defaultSlotFor(now),
        loggedAt: now,
        name: meal.mealName.length > FoodEntry.maxNameLength
            ? meal.mealName.substring(0, FoodEntry.maxNameLength)
            : meal.mealName,
        source: EntrySource.describe,
        confidence: meal.confidence,
        items: items,
        checkThese: CheckThese.fromCodes(codes),
        model: meal.model,
      );
      setState(() => _working = false);
      final saved = await showFoodDetailSheet(context, entry);
      if (saved && mounted) {
        Navigator.of(context).pop();
        context.go('/nutrition/diary');
      }
    } on FoodApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _notAvailable = e.isNotAvailableYet;
        _message = e.isNotAvailableYet
            ? l10n.foodDiaryNotAvailableYet
            : l10n.foodDescribeFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.foodAddDescribe,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('describe.text'),
            controller: _text,
            minLines: 2,
            maxLines: 4,
            maxLength: 200,
            decoration: InputDecoration(hintText: l10n.foodDescribeHint),
          ),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Text(_message!,
                  key: Key(_notAvailable ? 'describe.off' : 'describe.msg')),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('describe.go'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _working ? null : _go,
            child: _working
                ? Semantics(
                    label: l10n.foodDescribeWorking,
                    child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Text(l10n.foodDescribeSubmit),
          ),
        ],
      ),
    );
  }
}
