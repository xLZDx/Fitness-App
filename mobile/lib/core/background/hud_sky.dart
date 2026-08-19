/// The photograph the whole interface floats on, and the veil that makes text
/// survive it.
///
/// ## The assets were already in the app
///
/// The handoff ships ten 1440×2560 WebP scenes in `uploads/`. All ten are
/// **byte-identical** (MD5, 2026-08-19) to the ten already in
/// `assets/coach_bg/`, which the form coach stands the user's avatar in. So the
/// redesign's background library costs zero new bytes, raises no new licensing
/// question — the operator generated them, which is why that directory has no
/// attribution entry — and adds nothing to the APK.
///
/// The directory name is now too narrow for what it holds. Renaming it would
/// put a pubspec change, a form-coach change and a test change in the same diff
/// as a visual one, so it keeps its name and this comment carries the reason.
/// `hud_sky_test.dart` pins the two catalogues against each other so the
/// duplication cannot drift while it lasts.
///
/// ## What this does NOT do
///
/// It does not upload anything, and it must not start. The product invariant is
/// `PRODUCTION_IMAGE_COLLECTION = DISABLED`; a user-chosen background is a
/// **local presentation** choice and stays on the device. There is deliberately
/// no network dependency in this file for a future change to reach for.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/hud_tokens.dart';

/// The six phases, exactly as `Fitness Sky.dc.html` names and bounds them.
enum HudSkyPhase {
  night('night'),
  dawn('dawn'),
  morning('morning'),
  day('day'),
  golden('golden'),
  dusk('dusk');

  const HudSkyPhase(this.key);

  /// The string the token table and the handoff are keyed by.
  final String key;

  /// ```js
  /// if (h < 5 || h >= 22) return 'night';
  /// if (h < 7)  return 'dawn';
  /// if (h < 11) return 'morning';
  /// if (h < 16) return 'day';
  /// if (h < 19) return 'golden';
  /// return 'dusk';
  /// ```
  ///
  /// Transcribed rather than rewritten as a range table: the night band wraps
  /// midnight, so a table would need a special case the original does not have.
  static HudSkyPhase forHour(double hour) {
    final double h = hour.clamp(0, 23.99);
    if (h < 5 || h >= 22) return HudSkyPhase.night;
    if (h < 7) return HudSkyPhase.dawn;
    if (h < 11) return HudSkyPhase.morning;
    if (h < 16) return HudSkyPhase.day;
    if (h < 19) return HudSkyPhase.golden;
    return HudSkyPhase.dusk;
  }

  static HudSkyPhase forTime(DateTime now) =>
      forHour(now.hour + now.minute / 60);
}

/// Which curated set a phase draws from.
enum HudPhotoSet { a, b }

/// The ten scenes, and the phase each is assigned to in each set.
///
/// `08_coast_turquoise` appears in both sets (A/golden, B/day) and
/// `02_volcano` is night in both — that is what the handoff's `PHOTO_SETS`
/// says, not an error here.
abstract final class HudSky {
  static const String _dir = 'assets/coach_bg';

  /// Every scene, in filename order. The same ten files the form coach uses.
  static const List<String> catalogue = <String>[
    '$_dir/01_cliffs_moher.webp',
    '$_dir/02_volcano.webp',
    '$_dir/03_waterfall_dock.webp',
    '$_dir/04_fuji_sakura.webp',
    '$_dir/05_sunset_hills.webp',
    '$_dir/06_greek_terrace.webp',
    '$_dir/07_snow_peak_tarn.webp',
    '$_dir/08_coast_turquoise.webp',
    '$_dir/09_forest_lake.webp',
    '$_dir/10_beach_sunset.webp',
  ];

  static const Map<HudSkyPhase, String> _setA = <HudSkyPhase, String>{
    HudSkyPhase.dawn: '$_dir/01_cliffs_moher.webp',
    HudSkyPhase.morning: '$_dir/07_snow_peak_tarn.webp',
    HudSkyPhase.day: '$_dir/06_greek_terrace.webp',
    HudSkyPhase.golden: '$_dir/08_coast_turquoise.webp',
    HudSkyPhase.dusk: '$_dir/10_beach_sunset.webp',
    HudSkyPhase.night: '$_dir/02_volcano.webp',
  };

  static const Map<HudSkyPhase, String> _setB = <HudSkyPhase, String>{
    HudSkyPhase.dawn: '$_dir/04_fuji_sakura.webp',
    HudSkyPhase.morning: '$_dir/09_forest_lake.webp',
    HudSkyPhase.day: '$_dir/08_coast_turquoise.webp',
    HudSkyPhase.golden: '$_dir/03_waterfall_dock.webp',
    HudSkyPhase.dusk: '$_dir/05_sunset_hills.webp',
    HudSkyPhase.night: '$_dir/02_volcano.webp',
  };

  static Map<HudSkyPhase, String> assignments(HudPhotoSet set) =>
      set == HudPhotoSet.b ? _setB : _setA;

  static String assetFor(HudSkyPhase phase, HudPhotoSet set) =>
      assignments(set)[phase]!;

  /// `transition: opacity 1.6s ease`.
  static const Duration crossfade = Duration(milliseconds: 1600);

  /// Raw top-45%-of-frame 95th-percentile luminance (Rec.709, 0..255) for
  /// each bundled scene, measured directly against these exact WebP files --
  /// not a synthetic worst-case. Source of the accessibility BLOCKER this
  /// closes: an accessibility review's worst-case contrast calculation
  /// assumed a pure-white photo, which reads as a synthetic edge case; this
  /// is what the app's own ten shipped backgrounds actually measure in the
  /// zone the HUD draws status text over. Full per-image mean/p95/max table
  /// and measurement method in `DECISION_LOG.md`.
  static const Map<String, double> _topZoneP95 = <String, double>{
    '$_dir/01_cliffs_moher.webp': 228.69,
    '$_dir/02_volcano.webp': 145.08,
    '$_dir/03_waterfall_dock.webp': 174.97,
    '$_dir/04_fuji_sakura.webp': 242.26,
    '$_dir/05_sunset_hills.webp': 172.20,
    '$_dir/06_greek_terrace.webp': 222.37,
    '$_dir/07_snow_peak_tarn.webp': 227.69,
    '$_dir/08_coast_turquoise.webp': 152.33,
    '$_dir/09_forest_lake.webp': 240.84,
    '$_dir/10_beach_sunset.webp': 184.28,
  };

  /// The same measurement as [_topZoneP95], taken over the band dense content
  /// actually occupies: 40%-100% of the frame.
  ///
  /// This exists because a readability review of the shipped Workouts screen
  /// measured body copy at **1.39:1** and its call-to-action at **2.51:1**
  /// against the photograph, while the filter chips a few hundred pixels above
  /// them measured 6-7.75:1. The first hypothesis -- that [_topZoneP95] simply
  /// sampled the wrong zone -- was **disproved** by these numbers: across the
  /// ten assets the content band is not systematically brighter, and is
  /// *darker* for five of them. The real cause is that the veil gradient
  /// itself thins to `alpha * 0.74` at its 82% stop (`HudTokens.veilPositions`),
  /// which is exactly where dense content sits, and that `panel.fill` is white
  /// at 1.4% and therefore contributes no separation of its own.
  ///
  /// So this table does not adjust the veil. It sizes the **dense surface**
  /// tier ([denseSurfaceAlpha]) that content-heavy cards draw instead of the
  /// near-invisible `panel` fill.
  static const Map<String, double> _contentZoneP95 = <String, double>{
    '$_dir/01_cliffs_moher.webp': 181.01,
    '$_dir/02_volcano.webp': 150.65,
    '$_dir/03_waterfall_dock.webp': 182.45,
    '$_dir/04_fuji_sakura.webp': 242.84,
    '$_dir/05_sunset_hills.webp': 190.57,
    '$_dir/06_greek_terrace.webp': 172.14,
    '$_dir/07_snow_peak_tarn.webp': 209.25,
    '$_dir/08_coast_turquoise.webp': 163.01,
    '$_dir/09_forest_lake.webp': 242.40,
    '$_dir/10_beach_sunset.webp': 162.20,
  };

  /// Every bundled scene's [HudBackgroundProfile], derived from
  /// [_topZoneP95] and [_contentZoneP95] through the same formulas a
  /// locally-sampled user photo (D9) will use -- computed once here rather
  /// than hand-transcribed a second time, so the two can never drift against
  /// each other.
  static final Map<String, HudBackgroundProfile> backgroundProfiles =
      <String, HudBackgroundProfile>{
    for (final MapEntry<String, double> e in _topZoneP95.entries)
      e.key: HudBackgroundProfile(
        topZoneP95Luminance: e.value,
        recommendedVeilMultiplier:
            HudBackgroundProfile.multiplierForP95(e.value),
        contentZoneP95Luminance: _contentZoneP95[e.key]!,
        denseSurfaceAlpha:
            HudBackgroundProfile.denseAlphaForP95(_contentZoneP95[e.key]!),
      ),
  };

  /// The profile for whatever [HudSkySelection.imageKey] resolves to.
  ///
  /// A user-selected local photo (any key not in [backgroundProfiles], since
  /// that map only ever holds the ten bundled assets) has no profile yet --
  /// on-device sampling exists as [sampleBackgroundProfile] but nothing
  /// calls it, because the background-settings screen that would let a user
  /// choose a local photo, and the cache that would store the result, do not
  /// exist yet (D9). The neutral default is the pre-fix behaviour: no
  /// per-image boost, only the phase's own base veil.
  static HudBackgroundProfile profileFor(Object imageKey) =>
      backgroundProfiles[imageKey] ?? HudBackgroundProfile.neutral;
}

/// A background image's measured brightness in the zone the HUD draws status
/// text over, and the veil multiplier that keeps text readable against it.
@immutable
class HudBackgroundProfile {
  const HudBackgroundProfile({
    required this.topZoneP95Luminance,
    required this.recommendedVeilMultiplier,
    required this.contentZoneP95Luminance,
    required this.denseSurfaceAlpha,
  });

  /// 0..255. The 95th percentile, not the mean or the max: robust to a
  /// single hot pixel (a sun glint) that a max would overreact to, while
  /// still tracking a genuinely bright region a mean would understate.
  final double topZoneP95Luminance;

  /// Multiplies [HudSkySelection.veilScale] in [hudVeil], before that
  /// combined value is clamped to the same 0.55..1.6 range the user-facing
  /// control already respects -- a bright image cannot itself push the veil
  /// past the point the design already treats as "the photograph is gone".
  final double recommendedVeilMultiplier;

  /// 0..255, measured over the 40%-100% band. See [HudSky._contentZoneP95].
  final double contentZoneP95Luminance;

  /// The fill alpha a **dense content surface** needs over this picture for
  /// its body copy to stay readable -- the tier `HudPanel(dense: true)` draws.
  ///
  /// Not a style value: [denseAlphaForP95] solves it from the measurement.
  final double denseSurfaceAlpha;

  /// No per-image boost -- [hudVeil] behaves exactly as it did before this
  /// profile system existed.
  ///
  /// [denseSurfaceAlpha] deliberately does **not** take the same neutral
  /// treatment. An unmeasured picture (a user's own photo, D9) could be a
  /// white wall, and a dense card that assumed otherwise would put white text
  /// on white. So the fallback is [maxDenseAlpha] -- the protective end of the
  /// range, not the middle of it: unknown means assume the worst, and a
  /// measured photo can only ever relax it.
  static const HudBackgroundProfile neutral = HudBackgroundProfile(
    topZoneP95Luminance: 128,
    recommendedVeilMultiplier: 1.0,
    contentZoneP95Luminance: 255,
    denseSurfaceAlpha: maxDenseAlpha,
  );

  /// Enough presence to be a surface at all on the darkest bundled scene.
  static const double minDenseAlpha = 0.28;

  /// The point past which the card stops being glass and becomes a slab.
  ///
  /// This is a **cap on readability**, deliberately: the two brightest bundled
  /// scenes (`04_fuji_sakura`, `09_forest_lake`, content p95 ~242) reach it and
  /// therefore land at roughly 4.26:1 for a title and 3.61:1 for body copy
  /// rather than the 5.38:1 / 4.51:1 the other eight get. Raising it would buy
  /// that contrast by erasing the photograph, which is the one thing this
  /// design is for. Recorded rather than hidden, and pinned by name in
  /// `dense_surface_contrast_test.dart` so a future asset swap that changes
  /// which scenes pay this price fails a test instead of shipping.
  static const double maxDenseAlpha = 0.68;

  /// `#0A0C16`, the veil's own ink, in linear light. A dense card deepens the
  /// colour the veil is already made of, so it reads as more veil here rather
  /// than as a foreign panel.
  static const double _veilInkLinear = 0.0043;

  /// The weakest veil the dark theme can put over content: the lowest phase
  /// alpha (0.44, dawn and dusk) times the 0.74 dip at `veilPositions`' 82%
  /// stop. Assuming the weakest case here is what makes one alpha safe for
  /// every phase.
  static const double _weakestVeilAlpha = 0.3256;

  /// The composite luminance a dense surface must land at or below.
  ///
  /// Solved from the **secondary** text, not the title. Two rounds of that
  /// mattered: at 0.183 a pure-white heading clears 4.5:1 while the metadata
  /// under a programme name does not, and a first attempt at 0.155 assumed
  /// body copy at white@.90 when `HudTokens.textSecondary` is actually
  /// white@.80 — which the contrast test caught at 4.30:1. 0.145 is where the
  /// real token clears 4.5:1, and it carries the heading to 5.38:1 for free.
  static const double _targetCompositeLuminance = 0.145;

  /// The fill alpha that carries body copy to 4.5:1 over a picture measuring
  /// [p95Luminance] in the content band, clamped to [minDenseAlpha] ..
  /// [maxDenseAlpha].
  static double denseAlphaForP95(double p95Luminance) {
    final double photo = _srgbToLinear(p95Luminance / 255.0);
    final double backdrop = (1 - _weakestVeilAlpha) * photo +
        _weakestVeilAlpha * _veilInkLinear;
    if (backdrop <= _targetCompositeLuminance) return minDenseAlpha;
    final double alpha = (backdrop - _targetCompositeLuminance) /
        (backdrop - _veilInkLinear);
    return alpha.clamp(minDenseAlpha, maxDenseAlpha);
  }

  static double _srgbToLinear(double c) => c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// The formula behind every entry in [HudSky.backgroundProfiles], exposed
  /// so a locally-sampled user photo computes an identical recommendation,
  /// not merely a similar one.
  ///
  /// Bounds are measured, not guessed: 140 sits just under this app's own
  /// darkest bundled scene (`02_volcano`, p95 145.08) so it costs nothing;
  /// 250 sits just under the brightest (`04_fuji_sakura`, p95 242.26) so
  /// that scene is very nearly at the cap. The 0.45 ceiling on the boost
  /// itself keeps `veilScale 1.0 * multiplier` under the hard 1.6 clamp
  /// `hudVeil` already enforces, so the user's own density control always
  /// keeps some headroom above whatever the image alone earned.
  static double multiplierForP95(double p95Luminance) {
    const double baseline = 140.0;
    const double ceiling = 250.0;
    const double maxBoost = 0.45;
    final double t =
        ((p95Luminance - baseline) / (ceiling - baseline)).clamp(0.0, 1.0);
    return 1.0 + t * maxBoost;
  }
}

/// A one-time, entirely on-device luminance sample of an already-decoded
/// image's top [topFraction] -- the same zone [HudSky.backgroundProfiles]
/// measures for the bundled scenes. No network call, no upload: exists so a
/// user-selected local photo (D9) can get the same
/// [HudBackgroundProfile.recommendedVeilMultiplier] treatment, computed once
/// when the photo is picked and cached from there by that future screen,
/// never re-sampled on every frame or from inside a build method.
///
/// [stride] samples every Nth pixel in each dimension rather than every
/// pixel -- a full 1440-wide top zone is over a million pixels, and this is
/// a one-time cost the caller controls, not a per-frame one, but there is no
/// reason to pay for more precision than a percentile estimate needs.
Future<HudBackgroundProfile> sampleBackgroundProfile(
  ui.Image image, {
  double topFraction = 0.45,
  int stride = 4,
}) async {
  final ByteData? bytes =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return HudBackgroundProfile.neutral;

  return profileFromRgbaBytes(
    bytes.buffer.asUint8List(),
    width: image.width,
    height: image.height,
    topFraction: topFraction,
    stride: stride,
  );
}

/// The pure luminance math [sampleBackgroundProfile] runs, pulled out of the
/// `ui.Image`/`toByteData` decode path so it can be exercised with a
/// synthetic buffer in a plain unit test. `flutter test` on this host hangs
/// indefinitely inside `ui.decodeImageFromPixels`/`instantiateImageCodec`
/// regardless of input (confirmed with isolated diagnostic scripts, well
/// after the decode itself had already returned and been disposed -- an
/// environment limitation, not a defect here or a reason to leave this math
/// untested; see `DECISION_LOG.md`). [pixels] is raw RGBA8888, row-major,
/// exactly what [ui.ImageByteFormat.rawRgba] produces.
@visibleForTesting
HudBackgroundProfile profileFromRgbaBytes(
  Uint8List pixels, {
  required int width,
  required int height,
  double topFraction = 0.45,
  double contentStartFraction = 0.40,
  int stride = 4,
}) {
  if (pixels.isEmpty || width <= 0 || height <= 0) {
    return HudBackgroundProfile.neutral;
  }

  final int topRows = math.max(1, (height * topFraction).round());
  final int contentStart = (height * contentStartFraction).round();

  // Two bands in one pass over the pixels, because they overlap and decoding
  // is the expensive part: the top band sizes the veil, the content band
  // sizes the dense surface. Sampling twice would double the cost of the only
  // part of this that is not arithmetic.
  final List<double> topSamples = <double>[];
  final List<double> contentSamples = <double>[];
  for (int y = 0; y < height; y += stride) {
    final bool inTop = y < topRows;
    final bool inContent = y >= contentStart;
    if (!inTop && !inContent) continue;
    for (int x = 0; x < width; x += stride) {
      final int i = (y * width + x) * 4;
      if (i + 2 >= pixels.length) continue;
      final double r = pixels[i].toDouble();
      final double g = pixels[i + 1].toDouble();
      final double b = pixels[i + 2].toDouble();
      // Rec.709 coefficients -- the same ones `saturationFilter` in
      // `hud_tokens.dart` uses, for one consistent luminance definition
      // across the design system rather than two.
      final double lum = 0.213 * r + 0.715 * g + 0.072 * b;
      if (inTop) topSamples.add(lum);
      if (inContent) contentSamples.add(lum);
    }
  }
  if (topSamples.isEmpty) return HudBackgroundProfile.neutral;

  final double topP95 = _p95(topSamples);
  // A picture too short to have a content band is not a reason to guess: fall
  // back to the protective default rather than reusing the top-band number,
  // which measures a different part of the frame and would understate a
  // bright lower half exactly when it matters.
  final double contentP95 = contentSamples.isEmpty
      ? 255
      : _p95(contentSamples);
  return HudBackgroundProfile(
    topZoneP95Luminance: topP95,
    recommendedVeilMultiplier: HudBackgroundProfile.multiplierForP95(topP95),
    contentZoneP95Luminance: contentP95,
    denseSurfaceAlpha: HudBackgroundProfile.denseAlphaForP95(contentP95),
  );
}

double _p95(List<double> samples) {
  samples.sort();
  final int i = (samples.length * 0.95).floor().clamp(0, samples.length - 1);
  return samples[i];
}

/// What background a screen should show right now.
///
/// A value type rather than five parameters so a screen, a golden fixture and
/// the settings preview all describe the background the same way.
@immutable
class HudSkySelection {
  const HudSkySelection({
    required this.phase,
    this.photoSet = HudPhotoSet.a,
    this.userPhotoPath,
    this.veilScale = 1.0,
  });

  final HudSkyPhase phase;
  final HudPhotoSet photoSet;

  /// An absolute path to a file the user chose, on this device.
  ///
  /// A path, never bytes and never a URL: the picture stays where the picker
  /// left it and nothing here can send it anywhere.
  final String? userPhotoPath;

  /// The veil-density control from the background settings screen, as a
  /// multiplier on the phase alpha. 1.0 is the handoff's own value.
  ///
  /// **Floored at 0.55 by [veilFor], not here**, because a value that makes the
  /// interface unreadable is not a preference — see that method.
  final double veilScale;

  bool get usesUserPhoto => userPhotoPath != null;

  String get assetPath => HudSky.assetFor(phase, photoSet);

  /// Identity for the crossfade: two selections that resolve to the same
  /// picture must not fade, even if the phase changed (set A's `08_coast` is
  /// golden and set B's is day).
  Object get imageKey => userPhotoPath ?? assetPath;

  HudSkySelection copyWith({
    HudSkyPhase? phase,
    HudPhotoSet? photoSet,
    String? userPhotoPath,
    bool clearUserPhoto = false,
    double? veilScale,
  }) =>
      HudSkySelection(
        phase: phase ?? this.phase,
        photoSet: photoSet ?? this.photoSet,
        userPhotoPath:
            clearUserPhoto ? null : (userPhotoPath ?? this.userPhotoPath),
        veilScale: veilScale ?? this.veilScale,
      );

  @override
  bool operator ==(Object other) =>
      other is HudSkySelection &&
      other.phase == phase &&
      other.photoSet == photoSet &&
      other.userPhotoPath == userPhotoPath &&
      other.veilScale == veilScale;

  @override
  int get hashCode => Object.hash(phase, photoSet, userPhotoPath, veilScale);
}

/// The veil gradient for a phase, scaled by the user's density preference
/// AND by how bright this specific picture actually measures.
///
/// ## One flat alpha per phase was not enough
///
/// Before this, every image assigned to a phase shared that phase's veil
/// alpha regardless of how bright the actual photograph was -- `day`'s alpha
/// applied identically to `06_greek_terrace` (top-zone p95 222) and whatever
/// darker scene might join that phase later. An accessibility review's
/// worst-case contrast calculation assumed a pure-white photo and was
/// dismissed as synthetic until it was checked against the ten actual
/// shipped assets and found realistically reachable -- several genuinely
/// come within a few percent of pure white in the exact zone the HUD draws
/// status text over (see `HudSky.backgroundProfiles`). [HudSky.profileFor]
/// supplies a per-image multiplier on top of the phase's own alpha, so a
/// bright scene gets more veil without a uniformly darker experience on
/// every scene assigned to the same phase.
///
/// ## The floor is a safety rule, not a style rule
///
/// The interface is white text on an arbitrary photograph. Below roughly 55% of
/// the handoff's own alpha, a bright sky puts white-on-white on the screen and
/// the app stops being readable — including its refusals and its safety copy.
/// So the combined density (user preference × image multiplier) moves between
/// 0.55× and 1.6×, and asking for less than that yields the floor rather than
/// the request.
///
/// The cap exists for the opposite reason and is much less important: past
/// about 1.6× the photograph is gone and the design is a flat dark screen with
/// a decoding cost.
LinearGradient hudVeil(HudTokens tokens, HudSkySelection selection) {
  final double imageMultiplier =
      HudSky.profileFor(selection.imageKey).recommendedVeilMultiplier;
  final double scale = (selection.veilScale * imageMultiplier).clamp(0.55, 1.6);
  final List<Color> stops = tokens.veilStops[selection.phase.key]!;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: HudTokens.veilPositions,
    colors: <Color>[
      for (final Color c in stops)
        c.withValues(alpha: (c.a * scale).clamp(0.0, 1.0)),
    ],
  );
}

/// Paints the photograph, the veil, and the two diagonal light streaks, with a
/// 1.6 s crossfade when the picture changes.
///
/// ## Two layers, not six
///
/// The prototype mounts all six phase images at once and animates opacity. In a
/// browser that is six `<img>` elements the compositor may never decode. In
/// Flutter it is six full-resolution decodes held in memory — at 1440×2560 that
/// is roughly 14 MB each, 84 MB resident, for five pictures nobody is looking
/// at. So this holds the outgoing and the incoming frame and nothing else.
///
/// The incoming layer is only faded up **once its frame exists**. Starting the
/// fade at decode time would cross-dissolve into a blank rectangle, which on a
/// slow device is a visible white flash on every phase change.
class HudSkyBackground extends StatefulWidget {
  const HudSkyBackground({
    super.key,
    required this.selection,
    required this.child,
    this.showStreaks = true,
  });

  final HudSkySelection selection;
  final Widget child;

  /// The two rotated white gradients at the top of the device. Presentation
  /// only; off for the form coach, whose own video layer occupies that space.
  final bool showStreaks;

  @override
  State<HudSkyBackground> createState() => _HudSkyBackgroundState();
}

class _HudSkyBackgroundState extends State<HudSkyBackground> {
  /// The picture currently at full opacity.
  late Object _settled;

  /// The picture fading in, if any.
  Object? _incoming;

  @override
  void initState() {
    super.initState();
    _settled = widget.selection.imageKey;
  }

  @override
  void didUpdateWidget(HudSkyBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final Object next = widget.selection.imageKey;
    if (next == _incoming) return;
    if (next == _settled) {
      // The target reverted to what is already settled while a stale fade
      // toward a different picture was still in flight -- e.g. two phase
      // changes inside one 1.6s crossfade. Left alone, that fade's `onVisible`
      // still fires and settles on the picture nobody wants anymore, with
      // nothing left to correct it until the next unrelated selection change.
      // Cancelling it here, rather than only guarding in `_settle`, also drops
      // the now-pointless incoming decode instead of letting it finish unseen.
      if (_incoming != null) setState(() => _incoming = null);
      return;
    }
    setState(() => _incoming = next);
  }

  void _settle(Object key) {
    if (!mounted || _incoming != key) return;
    setState(() {
      _settled = key;
      _incoming = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final HudTokens tokens = context.hud;

    // Decode at the size actually painted, not at 1440 wide. On a 1080p phone
    // that is a third of the pixels and a third of the memory, for a picture
    // that is then scaled down anyway. `sizeOf`/`devicePixelRatioOf` scope
    // this widget's dependency to only that field, instead of `MediaQuery.of`
    // rebuilding it on every unrelated MediaQuery change (keyboard insets,
    // text scale, orientation).
    final int cacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(320, 1440);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // What shows before any decode completes, and behind a photograph with
        // transparency. Never nothing.
        ColoredBox(color: tokens.base),
        _layer(_settled, cacheWidth, opaque: true),
        if (_incoming != null) _layer(_incoming!, cacheWidth, opaque: false),
        DecoratedBox(
          decoration:
              BoxDecoration(gradient: hudVeil(tokens, widget.selection)),
        ),
        if (widget.showStreaks) const _LightStreaks(),
        // Published here rather than read from a global: the selection is
        // built in `MainShell` and was reachable by nothing below it, so a
        // dense card had no way to know what it was sitting on. Same
        // inherited-value shape as `HudQuality`, for the same reason -- one
        // screen can differ from the rest without a global to coordinate.
        HudSkyScope(
          profile: HudSky.profileFor(widget.selection.imageKey),
          child: widget.child,
        ),
      ],
    );
  }

  Widget _layer(Object key, int cacheWidth, {required bool opaque}) {
    final String path = key as String;
    final ImageProvider provider = path.startsWith('assets/')
        ? AssetImage(path)
        : FileImage(File(path)) as ImageProvider;

    return _CrossfadeLayer(
      key: ValueKey<Object>(key),
      provider: provider,
      cacheWidth: cacheWidth,
      startVisible: opaque,
      onVisible: opaque ? null : () => _settle(key),
    );
  }
}

/// Carries the current background's [HudBackgroundProfile] to everything drawn
/// on top of it, so a surface can size itself against the actual picture
/// instead of a fixed guess.
class HudSkyScope extends InheritedWidget {
  const HudSkyScope({
    super.key,
    required this.profile,
    required super.child,
  });

  final HudBackgroundProfile profile;

  /// Falls back to [HudBackgroundProfile.neutral] -- the protective end of the
  /// range -- when nothing above supplied one. A component pumped in a bare
  /// test tree, or drawn on a screen that mounts no sky, must not assume it is
  /// sitting on something dark.
  static HudBackgroundProfile of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<HudSkyScope>()
          ?.profile ??
      HudBackgroundProfile.neutral;

  @override
  bool updateShouldNotify(HudSkyScope oldWidget) =>
      oldWidget.profile.denseSurfaceAlpha != profile.denseSurfaceAlpha;
}

class _CrossfadeLayer extends StatefulWidget {
  const _CrossfadeLayer({
    super.key,
    required this.provider,
    required this.cacheWidth,
    required this.startVisible,
    this.onVisible,
  });

  final ImageProvider provider;
  final int cacheWidth;
  final bool startVisible;
  final VoidCallback? onVisible;

  @override
  State<_CrossfadeLayer> createState() => _CrossfadeLayerState();
}

class _CrossfadeLayerState extends State<_CrossfadeLayer> {
  late bool _visible = widget.startVisible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: HudSky.crossfade,
      curve: Curves.ease,
      onEnd: widget.onVisible,
      child: Image(
        image: ResizeImage.resizeIfNeeded(
            widget.cacheWidth, null, widget.provider),
        fit: BoxFit.cover,
        // A background that cannot load must not take the screen with it. The
        // veil and the base colour below still make the interface legible.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        frameBuilder: (BuildContext context, Widget child, int? frame,
            bool wasSynchronouslyLoaded) {
          final bool ready = wasSynchronouslyLoaded || frame != null;
          if (ready && !_visible) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_visible) setState(() => _visible = true);
            });
          }
          return child;
        },
      ),
    );
  }
}

/// `transform:rotate(24deg)` over two soft white gradients, top-left and
/// top-right. Purely decorative, and excluded from semantics so a screen reader
/// never announces them.
class _LightStreaks extends StatelessWidget {
  const _LightStreaks();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          children: <Widget>[
            Positioned(
              left: -60,
              top: -30,
              width: 220,
              height: 520,
              child: _Streak(alpha: 0.10),
            ),
            Positioned(
              right: -40,
              top: 60,
              width: 130,
              height: 520,
              child: _Streak(alpha: 0.07),
            ),
          ],
        ),
      ),
    );
  }
}

class _Streak extends StatelessWidget {
  const _Streak({required this.alpha});

  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 24 * 3.141592653589793 / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              const Color(0x00FFFFFF),
              HudTokens.decorativeHighlight.withValues(alpha: alpha),
              const Color(0x00FFFFFF),
            ],
          ),
        ),
      ),
    );
  }
}
