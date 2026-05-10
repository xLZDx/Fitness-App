import 'package:shared_preferences/shared_preferences.dart';

import 'moment.dart';
import 'moment_repository.dart';

/// SharedPreferences-backed moment repository. The persistence is local-
/// only (per-device) — that's fine for nurture prompts since reinstalling
/// is the only way to re-trigger them, which is the desired behavior.
class PrefsMomentRepository implements MomentRepository {
  PrefsMomentRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _shownPrefix = 'moment.shown.';
  static const _launchKey = 'moment.launch_count';
  static const _firstLaunchKey = 'moment.first_launch_at';
  static const _injuryUsesKey = 'moment.injury_filter_uses';

  static Future<PrefsMomentRepository> open() async {
    final p = await SharedPreferences.getInstance();
    return PrefsMomentRepository(p);
  }

  @override
  Future<bool> hasShown(MomentId id) async =>
      _prefs.getBool('$_shownPrefix${id.name}') ?? false;

  @override
  Future<void> markShown(MomentId id) async {
    await _prefs.setBool('$_shownPrefix${id.name}', true);
  }

  @override
  Future<int> launchCount() async => _prefs.getInt(_launchKey) ?? 0;

  @override
  Future<void> bumpLaunchCount() async {
    final n = (_prefs.getInt(_launchKey) ?? 0) + 1;
    await _prefs.setInt(_launchKey, n);
    if (!_prefs.containsKey(_firstLaunchKey)) {
      await _prefs.setString(
          _firstLaunchKey, DateTime.now().toIso8601String());
    }
  }

  @override
  Future<DateTime?> firstLaunchAt() async {
    final raw = _prefs.getString(_firstLaunchKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Future<int> injuryFilterUses() async =>
      _prefs.getInt(_injuryUsesKey) ?? 0;

  @override
  Future<void> bumpInjuryFilterUses() async {
    final n = (_prefs.getInt(_injuryUsesKey) ?? 0) + 1;
    await _prefs.setInt(_injuryUsesKey, n);
  }
}
