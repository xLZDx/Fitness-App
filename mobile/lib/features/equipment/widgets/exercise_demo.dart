import 'dart:async';

import 'package:flutter/material.dart';

/// Looping two-frame movement demo.
///
/// The catalog ships the start and end position of every exercise as bundled
/// images (public-domain source). Cross-fading between them at a controllable
/// tempo reads as a short video loop, but it is offline, a few kilobytes per
/// exercise, and cannot buffer or 404 mid-set.
class ExerciseDemo extends StatefulWidget {
  const ExerciseDemo({
    super.key,
    required this.frames,
    this.autoPlay = true,
  });

  /// Asset paths, in movement order. Fewer than two frames renders the first
  /// one as a still.
  final List<String> frames;
  final bool autoPlay;

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo> {
  static const _speeds = <String, int>{'0.5x': 1600, '1x': 900, '2x': 450};

  Timer? _timer;
  int _index = 0;
  String _speed = '1x';
  late bool _playing = widget.autoPlay && widget.frames.length > 1;

  @override
  void initState() {
    super.initState();
    if (_playing) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: _speeds[_speed]!),
      (_) => setState(() => _index = (_index + 1) % widget.frames.length),
    );
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _restart();
    } else {
      _timer?.cancel();
    }
  }

  void _setSpeed(String s) {
    setState(() => _speed = s);
    if (_playing) _restart();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Image.asset(
                    widget.frames[_index],
                    key: ValueKey<int>(_index),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        'Demo unavailable',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
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
