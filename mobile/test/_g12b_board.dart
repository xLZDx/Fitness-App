// A screenshot board for gate G1.2b.
//
// G1.2b is the only sub-gate of G1.2 that changes what a screen looks like, so
// "the tests still pass" is not the evidence it needs — the evidence is a
// picture. This renders the REAL widgets that were edited, not mock-ups of
// them, so what the image shows is what the app draws.
//
// Run it on the change, then on the parent commit, and compare:
//
//   flutter test test/_g12b_board.dart
//   git stash && flutter test test/_g12b_board.dart && git stash pop
//
// The output path carries the git description, so the two runs cannot
// overwrite each other by accident.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_palette.dart';
import 'package:fitness_app/core/theme/app_semantic_colors.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_thumb.dart';
import 'package:fitness_app/features/workouts/widgets/plate_calculator.dart';
import 'package:fitness_app/features/workouts/widgets/warmup_calculator.dart';

const _out = r'D:\test 2\Fitness App\core\screenshots';

Widget _board() => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One thumb, not ten: `ExerciseThumb(exercise: null)` derives its
          // gradient from `''.hashCode`, so ten of them are ten copies of the
          // same tile. The icon-on-gradient case is what it is here for; the
          // ramp below covers the other pairs.
          const Align(
            alignment: Alignment.centerLeft,
            child: ExerciseThumb(exercise: null, size: 56),
          ),
          const SizedBox(height: 16),
          // Cycles `tileGradients` by row, so four of the five pairs appear —
          // and row 1's counter badge is white @0.30 ON that gradient, the one
          // case where the ink lands on a translucent surface rather than the
          // artwork itself.
          const WarmupCalculator(initialWorkingKg: 80),
          const SizedBox(height: 16),
          const PlateCalculator(initialTargetKg: 60),
          // `GlassNavBar` is deliberately NOT here. It lays itself out against
          // the shell's constraints and overflows in this harness, in both the
          // before and the after shot — so it would only ever have shown the
          // harness. Its two edited lines are covered by measurement instead:
          // all five item gradients in `main_shell.dart` are aurora pairs, and
          // white scores 1.27–4.18 on every aurora hue.
        ],
      ),
    );

Future<void> _shoot(WidgetTester t, String name, Brightness b) async {
  final key = GlobalKey();
  // Phone-shaped: a 900pt-wide board is not a layout anyone sees, and the
  // ramp rows wrap differently at real width.
  t.view.physicalSize = const Size(420, 880);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  // The app's tokens, NOT `AppTheme`: that constructor resolves Inter through
  // Google Fonts the moment it is called, and a test has no network — the
  // failure lands after the test finishes, where `takeException` cannot reach
  // it, and reports a red run with two valid PNGs already written.
  // `_mockups.dart` avoids it the same way and for the same reason.
  //
  // The substitution is safe for what this board is FOR: every colour on it
  // comes from `AppSemanticColors` or `AppPalette`, which are consts the
  // widgets read directly. Only the letterforms are the platform's.
  final tokens =
      b == Brightness.dark ? AppSemanticColors.dark : AppSemanticColors.light;
  final theme = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppPalette.auroraViolet,
      brightness: b,
      surface: tokens.backgroundPrimary,
      onSurface: tokens.textPrimary,
      error: tokens.danger,
      outline: tokens.outline,
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
    fontFamily: 'MockSans',
  );

  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RepaintBoundary(
      key: key,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: b == Brightness.dark
                ? const [Color(0xFF16072E), Color(0xFF050214), Color(0xFF0B1233)]
                : const [Color(0xFFF6ECFF), Color(0xFFEDE3F8), Color(0xFFE4F0FF)],
          ),
        ),
        child: _board(),
      ),
    ),
  ));
  await t.pump(const Duration(milliseconds: 300));
  t.takeException();

  // toImage() completes on the real event loop, so awaiting it on the fake one
  // hangs until the suite times out. Same reason `_mockups.dart` does this.
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    final rev = Process.runSync('git', ['describe', '--always', '--dirty'],
            workingDirectory: r'D:\test 2\Fitness App')
        .stdout
        .toString()
        .trim();
    File('$_out/g12b_${name}_$rev.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    // Without a real face every label renders as tofu and every Icon as a box,
    // and the review ends up being about the harness instead of the colours.
    for (final (family, file) in const [
      ('MockSans', 'C:/Windows/Fonts/segoeui.ttf'),
      (
        'MaterialIcons',
        'D:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
      ),
    ]) {
      final f = File(file);
      if (!f.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
      await loader.load();
    }
  });

  testWidgets('g12b board dark', (t) => _shoot(t, 'dark', Brightness.dark));
  testWidgets('g12b board light', (t) => _shoot(t, 'light', Brightness.light));
}
