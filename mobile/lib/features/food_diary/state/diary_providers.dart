/// Food diary state (design s17, D-78, D-79): repositories, the bundled generic
/// table, the selected day, day totals against the plan, visibility, the
/// write actions and the search controller.
///
/// The data-notice acknowledgement (D-79) is the CALLER's job: the UI calls
/// `ensureDataNoticeAcknowledged` before the first diary write or food-AI call,
/// exactly like the weight log, so a declined notice defers the action and
/// nothing is lost.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/body_scan_flags.dart';
import '../../account_deletion/state/account_deletion_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../../nutrition_plan/state/nutrition_providers.dart';
import '../../nutrition_plan/state/weight_providers.dart';
import '../data/day_totals.dart';
import '../data/food_entry.dart';
import '../data/generic_foods.dart';
import 'diary_repository.dart';
import 'food_api.dart';
import 'meal_thumbnail_store.dart';

export 'firestore_diary_repository.dart'
    show FirestoreDiaryRepository, FirestoreSavedFoodsRepository;

final foodApiProvider = Provider<FoodApi>((_) => CallableFoodApi());

final diaryRepositoryProvider = Provider<FoodDiaryRepository>((ref) {
  final repo = InMemoryDiaryRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final savedFoodsRepositoryProvider = Provider<SavedFoodsRepository>((ref) {
  final repo = InMemorySavedFoodsRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Loads the bundled generic foods (and the RU names) once.
final genericFoodTableProvider = FutureProvider<GenericFoodTable>((ref) async {
  final foods =
      await rootBundle.loadString('assets/nutrition/generic_foods_v1.json');
  String? ru;
  try {
    ru = await rootBundle.loadString('assets/nutrition/generic_foods_ru.json');
  } catch (_) {
    ru = null;
  }
  return GenericFoodTable.parse(foods, ruJson: ru);
});

String dayKeyOf(DateTime d) => DateFormat('yyyy-MM-dd', 'en').format(d);

/// The local day the diary shows; starts at today.
final selectedDiaryDayProvider = StateProvider<String>(
  (ref) => dayKeyOf(ref.watch(nutritionClockProvider)()),
);

/// Keeps [selectedDiaryDayProvider] on the real date: when the clock day has
/// moved on (the app was open or backgrounded across midnight) and the user is
/// still on the day that WAS today, the selection follows to the new today. A
/// day the user picked deliberately is left alone, so a new entry is never
/// saved to yesterday by accident. Watch it from the diary page; it re-checks
/// whenever the app resumes.
class DiaryDayFollower with WidgetsBindingObserver {
  DiaryDayFollower(this._ref);

  final Ref _ref;
  late String _lastToday = dayKeyOf(_ref.read(nutritionClockProvider)());

  /// Moves the selection to today when it was on the previous today.
  void sync() {
    final today = dayKeyOf(_ref.read(nutritionClockProvider)());
    if (today == _lastToday) return;
    final selected = _ref.read(selectedDiaryDayProvider);
    if (selected == _lastToday) {
      _ref.read(selectedDiaryDayProvider.notifier).state = today;
    }
    _lastToday = today;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }
}

final diaryDayFollowerProvider = Provider<DiaryDayFollower>((ref) {
  final follower = DiaryDayFollower(ref);
  try {
    WidgetsBinding.instance.addObserver(follower);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(follower));
  } catch (e) {
    debugPrint('diary: lifecycle observer unavailable (${e.runtimeType})');
  }
  return follower;
});

/// The diary is shown only to a user for whom the plan numbers are allowed;
/// for `referProfessional` (and while the verdict is unknown) it is hidden
/// entirely (D-9, D-55). Needs-answer / needs-profile users are sent to the
/// profile flow by the page, never shown numbers.
final diaryVisibleProvider = Provider<bool>((ref) {
  final v = ref.watch(nutritionEligibilityProvider);
  return v != null && v.allowsNumbers;
});

/// Entries of one day, oldest first.
final diaryDayEntriesProvider =
    StreamProvider.family<List<FoodEntry>, String>((ref, day) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(diaryRepositoryProvider).watchDay(user.uid, day);
});

final savedFoodsProvider = StreamProvider<List<SavedFood>>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(savedFoodsRepositoryProvider).watchAll(user.uid);
});

/// The day targets from the stored plan, or null without an eligible plan.
final dayTargetsProvider = Provider<DayTargets?>((ref) {
  final plan = ref.watch(nutritionPlanProvider).valueOrNull;
  if (plan == null) return null;
  final low = plan.kcalRange.low.toDouble();
  final high = plan.kcalRange.high.toDouble();
  return DayTargets(
    kcalLow: low,
    kcalTarget: (low + high) / 2,
    kcalHigh: high,
    proteinMinG: plan.protein.minG.toDouble(),
  );
});

/// Totals of one day against the targets; null targets give a plain sum with
/// an unbounded range so no "below range" status is ever invented.
final dayTotalsProvider = Provider.family<DayTotals?, String>((ref, day) {
  final entries = ref.watch(diaryDayEntriesProvider(day)).valueOrNull;
  if (entries == null) return null;
  final targets = ref.watch(dayTargetsProvider) ??
      const DayTargets(
          kcalLow: 0, kcalTarget: 0, kcalHigh: double.maxFinite);
  return computeDayTotals([for (final e in entries) e.totals], targets);
});

/// What a diary write did.
enum DiaryWriteStatus { saved, invalid, unavailable, failed }

/// Create / replace / delete of entries and saved foods.
class FoodDiaryActions {
  FoodDiaryActions(this._ref);

  final Ref _ref;

  String? _uid() {
    final uid = _ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) return null;
    // The deletion fence: no write while this account is being deleted.
    if (_ref.read(accountBeingDeletedUidProvider) == uid) return null;
    return uid;
  }

  Future<DiaryWriteStatus> saveEntry(FoodEntry entry) async {
    final uid = _uid();
    if (uid == null) return DiaryWriteStatus.unavailable;
    if (entry.validate().isNotEmpty) return DiaryWriteStatus.invalid;
    try {
      await _ref.read(diaryRepositoryProvider).put(uid, entry);
      return DiaryWriteStatus.saved;
    } on FormatException {
      return DiaryWriteStatus.invalid;
    } catch (_) {
      return DiaryWriteStatus.failed;
    }
  }

  Future<DiaryWriteStatus> deleteEntry(String entryId) async {
    final uid = _uid();
    if (uid == null) return DiaryWriteStatus.unavailable;
    try {
      await _ref.read(diaryRepositoryProvider).delete(uid, entryId);
      // C24: a private meal thumbnail lives and dies with its entry.
      await _ref.read(mealThumbnailDeleterProvider)(entryId);
      return DiaryWriteStatus.saved;
    } catch (_) {
      return DiaryWriteStatus.failed;
    }
  }

  Future<DiaryWriteStatus> saveFood(SavedFood food) async {
    final uid = _uid();
    if (uid == null) return DiaryWriteStatus.unavailable;
    if (food.validate().isNotEmpty) return DiaryWriteStatus.invalid;
    try {
      await _ref.read(savedFoodsRepositoryProvider).put(uid, food);
      return DiaryWriteStatus.saved;
    } on FormatException {
      return DiaryWriteStatus.invalid;
    } catch (_) {
      return DiaryWriteStatus.failed;
    }
  }

  Future<DiaryWriteStatus> deleteSavedFood(String id) async {
    final uid = _uid();
    if (uid == null) return DiaryWriteStatus.unavailable;
    try {
      await _ref.read(savedFoodsRepositoryProvider).delete(uid, id);
      return DiaryWriteStatus.saved;
    } catch (_) {
      return DiaryWriteStatus.failed;
    }
  }
}

final foodDiaryActionsProvider =
    Provider<FoodDiaryActions>((ref) => FoodDiaryActions(ref));

/// Client id for a new entry (idempotent retries reuse it).
String newEntryId(DateTime now) =>
    'e${now.microsecondsSinceEpoch.toRadixString(36)}'
    '${(now.hashCode & 0xfffff).toRadixString(36)}';

// ---------------------------------------------------------------- search

enum SearchPhase { idle, tooShort, loading, results, empty, notAvailable, error }

class FoodSearchState {
  const FoodSearchState({
    this.phase = SearchPhase.idle,
    this.query = '',
    this.local = const [],
    this.remote = const [],
    this.rateLimited = false,
  });

  final SearchPhase phase;
  final String query;

  /// Bundled generic matches (instant, offline).
  final List<GenericFoodHit> local;

  /// Server matches (packaged foods / USDA) after an explicit submit.
  final List<FoodCandidate> remote;
  final bool rateLimited;

  FoodSearchState copyWith({
    SearchPhase? phase,
    String? query,
    List<GenericFoodHit>? local,
    List<FoodCandidate>? remote,
    bool? rateLimited,
  }) =>
      FoodSearchState(
        phase: phase ?? this.phase,
        query: query ?? this.query,
        local: local ?? this.local,
        remote: remote ?? this.remote,
        rateLimited: rateLimited ?? this.rateLimited,
      );
}

/// Search controller: the bundled table answers instantly while typing; the
/// SERVER is called only on explicit submit, never for fewer than
/// [minChars] characters, at most once per [debounce] (a second submit inside
/// the window replaces the pending one) and the last results are cached per
/// (query, language) so a repeat costs nothing.
class FoodSearchController extends StateNotifier<FoodSearchState> {
  FoodSearchController({
    required this.api,
    required GenericFoodTable table,
    required this.serverEnabled,
    required this.languageCode,
    this.debounce = const Duration(milliseconds: 600),
  })  : _table = table,
        super(const FoodSearchState());

  static const int minChars = 3;

  final FoodApi api;
  GenericFoodTable _table;
  GenericFoodTable get table => _table;
  final bool serverEnabled;
  final String languageCode;
  final Duration debounce;

  Timer? _timer;
  bool _tableFailed = false;
  String? _cacheKey;
  List<FoodCandidate> _cache = const [];

  /// Typing: local results only, no network.
  void onChanged(String raw) {
    final q = raw.trim();
    if (q.length < minChars) {
      state = FoodSearchState(
        phase: q.isEmpty ? SearchPhase.idle : SearchPhase.tooShort,
        query: q,
      );
      return;
    }
    final hits = _table.search(q);
    state = FoodSearchState(
      phase: hits.isEmpty && !serverEnabled
          ? (_tableFailed ? SearchPhase.error : SearchPhase.empty)
          : SearchPhase.results,
      query: q,
      local: hits,
      remote: _cacheKey == _key(q) ? _cache : const [],
    );
  }

  /// The bundled table finished loading. The search keeps its query, phase,
  /// server results and cache; only the local hits are recomputed.
  void setTable(GenericFoodTable table) {
    if (!mounted) return;
    _table = table;
    _tableFailed = false;
    final q = state.query;
    if (q.length < minChars) return;
    final hits = table.search(q);
    state = state.copyWith(
      local: hits,
      phase: (state.phase == SearchPhase.empty ||
                  state.phase == SearchPhase.error) &&
              hits.isNotEmpty
          ? SearchPhase.results
          : state.phase,
    );
  }

  /// The bundled table could not be loaded: "nothing found" would be a lie
  /// for a search that never had data, so an empty result is an error.
  void setTableFailed() {
    if (!mounted) return;
    _tableFailed = true;
    if (state.phase == SearchPhase.empty && state.local.isEmpty) {
      state = state.copyWith(phase: SearchPhase.error);
    }
  }

  String _key(String q) => '$languageCode|${q.toLowerCase()}';

  /// Explicit submit (button or keyboard action).
  void submit(String raw) {
    final q = raw.trim();
    onChanged(q);
    if (q.length < minChars || !serverEnabled) return;
    if (_cacheKey == _key(q)) return;
    _timer?.cancel();
    state = state.copyWith(phase: SearchPhase.loading);
    _timer = Timer(debounce, () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    try {
      final res = await api.searchFoods(q, languageCode: languageCode);
      if (!mounted || state.query != q) return;
      _cacheKey = _key(q);
      _cache = res.results;
      state = state.copyWith(
        phase: state.local.isEmpty && res.results.isEmpty
            ? SearchPhase.empty
            : SearchPhase.results,
        remote: res.results,
        rateLimited: false,
      );
    } on FoodApiException catch (e) {
      if (!mounted || state.query != q) return;
      if (e.isNotAvailableYet) {
        state = state.copyWith(phase: SearchPhase.notAvailable);
      } else {
        state = state.copyWith(
          phase: state.local.isNotEmpty ? SearchPhase.results : SearchPhase.error,
          rateLimited: e.failure == FoodApiFailure.rateLimited,
        );
      }
    } catch (e) {
      // Any other failure (parsing, platform, unexpected) is a closed error
      // state, never an unhandled error from a timer.
      debugPrint('food search failed (${e.runtimeType})');
      if (!mounted || state.query != q) return;
      state = state.copyWith(
        phase: state.local.isNotEmpty ? SearchPhase.results : SearchPhase.error,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Arguments are the table and language; the server flag is read here.
final foodSearchControllerProvider = StateNotifierProvider.autoDispose
    .family<FoodSearchController, FoodSearchState, String>((ref, lang) {
  // The table is read, not watched: its load must not rebuild the controller
  // (that would drop the query, the results and the cache the user has).
  final controller = FoodSearchController(
    api: ref.watch(foodApiProvider),
    table: ref.read(genericFoodTableProvider).valueOrNull ??
        GenericFoodTable.empty(),
    serverEnabled: ref.watch(bodyScanFlagsProvider).foodLookup,
    languageCode: lang,
  );
  ref.listen<AsyncValue<GenericFoodTable>>(genericFoodTableProvider,
      (previous, next) {
    next.when(
      data: controller.setTable,
      error: (_, __) => controller.setTableFailed(),
      loading: () {},
    );
  }, fireImmediately: false);
  if (ref.read(genericFoodTableProvider).hasError) controller.setTableFailed();
  return controller;
});
