import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/glass.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Pure logic separated from the widget so the countdown is unit-testable
/// without flutter_test. Holds a remaining-seconds value + an optional
/// notion of "auto-started", and ticks at 1Hz.
class RestTimerController extends ChangeNotifier {
  RestTimerController({this.totalSeconds = 90})
      : _remaining = totalSeconds,
        _running = false;

  final int totalSeconds;
  int _remaining;
  bool _running;
  Timer? _timer;

  int get remaining => _remaining;
  bool get isRunning => _running;
  double get progress =>
      totalSeconds == 0 ? 0 : 1 - (_remaining / totalSeconds);

  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _remaining = totalSeconds;
    notifyListeners();
  }

  void _tick() {
    if (_remaining > 0) _remaining--;
    if (_remaining == 0) {
      _timer?.cancel();
      _timer = null;
      _running = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Glass-card rest timer. Triggers a haptic pulse at 0s. Designed to be
/// surfaced just below the "Mark complete" button after a set is logged.
///
/// Default of 90s matches the rest most commercial gyms recommend for
/// hypertrophy work; compound lifts (barbell squat / deadlift / bench /
/// OHP) take 180s — passed via [seconds] from the calling page.
class RestTimer extends StatefulWidget {
  const RestTimer({
    super.key,
    this.seconds = 90,
    this.autoStart = true,
    this.onComplete,
  });

  final int seconds;
  final bool autoStart;
  final VoidCallback? onComplete;

  @override
  State<RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends State<RestTimer> {
  late final RestTimerController _ctrl =
      RestTimerController(totalSeconds: widget.seconds);
  bool _firedComplete = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTick);
    if (widget.autoStart) _ctrl.start();
  }

  void _onTick() {
    setState(() {});
    if (_ctrl.remaining == 0 && !_firedComplete) {
      _firedComplete = true;
      HapticFeedback.heavyImpact();
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  String _format(int s) {
    final m = (s ~/ 60).toString();
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _ctrl.remaining == 0;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _ctrl.progress.clamp(0.0, 1.0),
                  strokeWidth: 4,
                  backgroundColor:
                      scheme.onSurface.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    done
                        ? AppPalette.auroraLime
                        : AppPalette.auroraBlue,
                  ),
                ),
                Text(
                  _format(_ctrl.remaining),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  done ? 'Rest complete — next set' : 'Rest timer',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  done
                      ? 'Tap to reset for the next round.'
                      : 'Auto-stops your phone — focus on the next set.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _ctrl.isRunning
                ? AppLocalizations.of(context).workoutsPause
                : (done ? AppLocalizations.of(context).workoutsReset : AppLocalizations.of(context).commonStart),
            icon: Icon(_ctrl.isRunning
                ? Icons.pause_rounded
                : (done ? Icons.refresh_rounded : Icons.play_arrow_rounded)),
            onPressed: () {
              if (done) {
                _firedComplete = false;
                _ctrl.reset();
                _ctrl.start();
              } else if (_ctrl.isRunning) {
                _ctrl.pause();
              } else {
                _ctrl.start();
              }
            },
          ),
        ],
      ),
    );
  }
}
