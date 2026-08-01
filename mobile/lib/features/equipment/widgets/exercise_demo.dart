import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Looping movement demo built from the catalogue's position frames.
///
/// Two frames is the ceiling, and that is a property of the source rather than
/// of this widget: all 873 exercises in the public-domain free-exercise-db ship
/// exactly two images, and the Everkinetic files on Wikimedia Commons that look
/// like animations (`Standing-biceps-curl-1.gif`) are single-frame stills — the
/// suffix is the position number. Every genuinely animated exercise library
/// found is commercially licensed. So the job here is to make two frames read as
/// a repetition rather than as a slideshow.
///
/// The cadence is what does that: hold the start position, move smoothly, hold
/// the end position, then reverse. A constant-rate cross-fade — what this used
/// to do, on a periodic Timer — reads as a dissolve between two photographs,
/// because there is no moment where either position is simply *held*, which is
/// what a real rep looks like.
///
/// Offline, a few kilobytes per exercise, and it cannot buffer or 404 mid-set.
class ExerciseDemo extends StatefulWidget {
  const ExerciseDemo({
    super.key,
    required this.frames,
    this.autoPlay = true,
  });

  /// Asset paths, in movement order. Fewer than two renders the first as a still.
  final List<String> frames;
  final bool autoPlay;

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo>
    with SingleTickerProviderStateMixin {
  /// Milliseconds for one transition, hold included.
  ///
  /// The same four labels as the video block, so the two demo paths offer the
  /// same control rather than two different ones — the operator's complaint
  /// about the catalog was that it does not look like one thing.
  static const _speeds = <String, int>{
    '0.5x': 1800,
    '1x': 900,
    '2x': 450,
    '3x': 300,
  };

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _speeds[_speed]!),
  )..addStatusListener(_onStatus);

  /// Eased travel with a genuine pause at each end.
  late final Animation<double> _t = _controller.drive(
    TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 20),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 20),
    ]),
  );

  int _index = 0;
  String _speed = '1x';
  late bool _playing = widget.autoPlay && widget.frames.length > 1;

  int get _next =>
      widget.frames.isEmpty ? 0 : (_index + 1) % widget.frames.length;

  @override
  void initState() {
    super.initState();
    if (_playing) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Advances to the next frame at the end of each transition.
  ///
  /// Driven by completion rather than `repeat(reverse: true)` so the same code
  /// handles more than two frames if the catalogue ever gains them.
  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_playing) return;
    setState(() => _index = _next);
    _controller
      ..reset()
      ..forward();
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _controller.forward();
    } else {
      _controller.stop();
    }
  }

  void _setSpeed(String s) {
    setState(() => _speed = s);
    _controller.duration = Duration(milliseconds: _speeds[s]!);
    if (_playing) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black12),
                AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      // Both frames stay mounted, so neither is decoded mid-loop.
                      Opacity(
                        opacity: 1 - _t.value,
                        child: _Frame(asset: widget.frames[_index]),
                      ),
                      if (widget.frames.length > 1)
                        Opacity(
                          opacity: _t.value,
                          child: _Frame(asset: widget.frames[_next]),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: IconButton.filledTonal(
                    key: const Key('exercise-demo-play'),
                    onPressed: widget.frames.length > 1 ? _toggle : null,
                    icon: Icon(_playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Row(
                    children: [
                      for (final s in _speeds.keys)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: ChoiceChip(
                            label: Text(s),
                            selected: _speed == s,
                            onSelected: (_) => _setSpeed(s),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _Frame extends StatelessWidget {
  const _Frame({required this.asset});

  /// A bundled asset path, OR an http(s) URL. Catalog entries added after
  /// the original 66-exercise bundle (Free Exercise DB round 2, 2026-07-30)
  /// ship as network stills rather than bundled assets -- 120+ more
  /// exercises x 2 photos each would repeat the APK-size regression the
  /// first bundle caused.
  final String asset;

  bool get _isNetwork => asset.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget errorBuilder(BuildContext _, Object __, StackTrace? ___) => Center(
          child: Text(
            AppLocalizations.of(context).equipmentDemoUnavailable,
            style: theme.textTheme.bodySmall,
          ),
        );
    if (_isNetwork) {
      return Image.network(
        asset,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: errorBuilder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const _Warming(),
      );
    }
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: errorBuilder,
    );
  }
}

class _Warming extends StatelessWidget {
  const _Warming();

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}
