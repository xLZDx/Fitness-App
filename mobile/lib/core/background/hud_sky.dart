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

/// The veil gradient for a phase, scaled by the user's density preference.
///
/// ## The floor is a safety rule, not a style rule
///
/// The interface is white text on an arbitrary photograph. Below roughly 55% of
/// the handoff's own alpha, a bright sky puts white-on-white on the screen and
/// the app stops being readable — including its refusals and its safety copy.
/// So the density control moves between 0.55× and 1.6×, and asking for less
/// than that yields the floor rather than the request.
///
/// The cap exists for the opposite reason and is much less important: past
/// about 1.6× the photograph is gone and the design is a flat dark screen with
/// a decoding cost.
LinearGradient hudVeil(HudTokens tokens, HudSkySelection selection) {
  final double scale = selection.veilScale.clamp(0.55, 1.6);
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
        widget.child,
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
