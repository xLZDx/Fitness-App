// S03 mode flags (design 4.2, contract 4.1): Train and Body are always
// available; Ride and Explore follow the build switches (default off).
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_flags.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default flags: train and body available, ride and explore coming '
      'later', () {
    const f = ModeFlags();
    final t = f.availabilityTable;
    expect(t[AppMode.train], ModeAvailability.available);
    expect(t[AppMode.body], ModeAvailability.available);
    expect(t[AppMode.ride], ModeAvailability.comingLater);
    expect(t[AppMode.explore], ModeAvailability.comingLater);
    expect(t.length, AppMode.values.length);
  });

  test('the default flag table equals the default availability table', () {
    expect(const ModeFlags().availabilityTable, kDefaultModeAvailability);
  });

  test('the compile-time default build has ride and explore off', () {
    expect(ModeFlags.compileTime.rideEnabled, isFalse);
    expect(ModeFlags.compileTime.exploreEnabled, isFalse);
  });

  test('each switch turns on exactly its own mode', () {
    final ride = const ModeFlags(rideEnabled: true).availabilityTable;
    expect(ride[AppMode.ride], ModeAvailability.available);
    expect(ride[AppMode.explore], ModeAvailability.comingLater);
    final explore = const ModeFlags(exploreEnabled: true).availabilityTable;
    expect(explore[AppMode.explore], ModeAvailability.available);
    expect(explore[AppMode.ride], ModeAvailability.comingLater);
  });

  test('a mode missing from a table is coming later (fail closed)', () {
    expect(availabilityOfMode(AppMode.ride, table: const {}),
        ModeAvailability.comingLater);
    expect(availabilityOfMode(AppMode.train, table: const {}),
        ModeAvailability.comingLater);
  });

  test('modeFlagsProvider defaults to compileTime and can be overridden', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(modeFlagsProvider), same(ModeFlags.compileTime));
    final o = ProviderContainer(overrides: [
      modeFlagsProvider.overrideWithValue(const ModeFlags(rideEnabled: true)),
    ]);
    addTearDown(o.dispose);
    expect(o.read(modeFlagsProvider).rideEnabled, isTrue);
  });
}
