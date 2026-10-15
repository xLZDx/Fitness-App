/// Body-fat trend chart with an accessible alternative (design s12.5, D-85).
///
/// The painted chart is excluded from semantics. ONE summary node carries the
/// sentence ("Smoothed trend 24.1 percent, down 0.8 points over 4 weeks") and an
/// "Expand" action that opens the data table (date, reading with range,
/// smoothed value, outlier flag; each row has a semantic label). Dots (single
/// readings, with range whiskers) and the line (smoothed trend) differ by shape
/// and a legend, never by colour alone; outliers are drawn as hollow diamonds.
/// All numbers and dates go through the active locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../data/scan_trend.dart';

/// The chart shows at most this many latest scans.
const int kTrendChartMaxPoints = 12;

/// The summary sentence, locale aware.
String trendSummaryText(
  AppLocalizations l10n,
  TrendSeries series,
  ChangeLabel? label,
) {
  final loc = l10n.localeName;
  final num1 = NumberFormat('0.0', loc);
  final value = num1.format(series.smoothedNow);
  if (label == null || series.points.length < 2) {
    return l10n.bodyScanChartSummaryFew(value);
  }
  final first = series.points.first;
  final spanDays =
      series.latest.reading.at.difference(first.reading.at).inDays;
  final weeks = NumberFormat('0', loc).format((spanDays / 7).round().clamp(1, 999));
  final pts = num1.format((series.smoothedNow - first.smoothed).abs());
  return switch (label) {
    ChangeLabel.down => l10n.bodyScanChartSummaryDown(value, pts, weeks),
    ChangeLabel.up => l10n.bodyScanChartSummaryUp(value, pts, weeks),
    ChangeLabel.noMeaningfulChange =>
      l10n.bodyScanChartSummaryFlat(value, weeks),
  };
}

class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.series,
    required this.trendLabel,
    this.modelChangeAt = const [],
  });

  final TrendSeries series;
  final ChangeLabel? trendLabel;
  final List<DateTime> modelChangeAt;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final all = widget.series.points;
    final points = all.length > kTrendChartMaxPoints
        ? all.sublist(all.length - kTrendChartMaxPoints)
        : all;
    final summary =
        trendSummaryText(l10n, widget.series, widget.trendLabel);
    final newEstimator = widget.modelChangeAt.isNotEmpty;
    return GlassCard(
      key: const Key('bodyScan.chart.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.bodyScanChartTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: hud.textPrimary)),
          ),
          const SizedBox(height: 8),
          // ONE summary node with the expand action.
          Semantics(
            key: const Key('bodyScan.chart.summary'),
            container: true,
            label: summary,
            excludeSemantics: true,
            customSemanticsActions: {
              CustomSemanticsAction(
                  label: _expanded
                      ? l10n.bodyScanChartCollapse
                      : l10n.bodyScanChartExpand): _toggle,
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: hud.textPrimary)),
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: CustomPaint(
                      key: const Key('bodyScan.chart.paint'),
                      painter: _TrendPainter(
                        points: points,
                        dot: hud.textSecondary,
                        line: hud.accent,
                        grid: hud.divider,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: hud.textSecondary),
              const SizedBox(width: 4),
              Icon(Icons.show_chart, size: 16, color: hud.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.bodyScanChartLegend,
                    key: const Key('bodyScan.chart.legend'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: hud.textSecondary)),
              ),
            ],
          ),
          if (newEstimator)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.flag_outlined, size: 16, color: hud.warning),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(l10n.bodyScanChartNewEstimator,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: hud.textSecondary)),
                  ),
                ],
              ),
            ),
          TextButton(
            key: const Key('bodyScan.chart.toggle'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _toggle,
            child: Text(_expanded
                ? l10n.bodyScanChartCollapse
                : l10n.bodyScanChartExpand),
          ),
          if (_expanded) _DataTable(points: points),
        ],
      ),
    );
  }
}

class _DataTable extends StatelessWidget {
  const _DataTable({required this.points});

  final List<SmoothedPoint> points;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final loc = l10n.localeName;
    final n1 = NumberFormat('0.0', loc);
    final date = DateFormat.yMd(loc);
    final head = theme.textTheme.labelMedium?.copyWith(color: hud.textSecondary);
    final cell = theme.textTheme.bodySmall?.copyWith(color: hud.textPrimary);
    Widget row(List<String> cells, TextStyle? style) => Row(
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: i == 1 ? 3 : 2,
                child: Text(cells[i], style: style),
              ),
          ],
        );
    return Column(
      key: const Key('bodyScan.chart.table'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: row([
            l10n.bodyScanChartColDate,
            l10n.bodyScanChartColReading,
            l10n.bodyScanChartColSmoothed,
            l10n.bodyScanChartColOutlier,
          ], head),
        ),
        for (final p in points.reversed)
          Semantics(
            container: true,
            excludeSemantics: true,
            label: l10n.bodyScanChartRowLabel(
              date.format(p.reading.at),
              n1.format(p.reading.value),
              n1.format(p.reading.value - p.reading.halfWidth),
              n1.format(p.reading.value + p.reading.halfWidth),
              n1.format(p.smoothed),
              p.isOutlier ? l10n.bodyScanChartYes : l10n.bodyScanChartNo,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: row([
                date.format(p.reading.at),
                '${n1.format(p.reading.value)} '
                    '(${n1.format(p.reading.value - p.reading.halfWidth)}-'
                    '${n1.format(p.reading.value + p.reading.halfWidth)})',
                n1.format(p.smoothed),
                p.isOutlier ? l10n.bodyScanChartYes : l10n.bodyScanChartNo,
              ], cell),
            ),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.dot,
    required this.line,
    required this.grid,
  });

  final List<SmoothedPoint> points;
  final Color dot;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final p in points) {
      lo = lo < p.reading.value - p.reading.halfWidth
          ? lo
          : p.reading.value - p.reading.halfWidth;
      hi = hi > p.reading.value + p.reading.halfWidth
          ? hi
          : p.reading.value + p.reading.halfWidth;
      if (p.smoothed < lo) lo = p.smoothed;
      if (p.smoothed > hi) hi = p.smoothed;
    }
    if (hi - lo < 1) {
      hi += 0.5;
      lo -= 0.5;
    }
    const pad = 12.0;
    final t0 = points.first.reading.at.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.reading.at.millisecondsSinceEpoch.toDouble();
    double x(SmoothedPoint p) => points.length == 1 || t1 == t0
        ? size.width / 2
        : pad +
            (p.reading.at.millisecondsSinceEpoch - t0) /
                (t1 - t0) *
                (size.width - 2 * pad);
    double y(double v) =>
        pad + (hi - v) / (hi - lo) * (size.height - 2 * pad);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), gridPaint);

    final linePaint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(x(points[i]), y(points[i].smoothed));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, linePaint);

    final whisker = Paint()
      ..color = dot
      ..strokeWidth = 1.5;
    final fill = Paint()..color = dot;
    final ring = Paint()
      ..color = dot
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in points) {
      final cx = x(p);
      canvas.drawLine(Offset(cx, y(p.reading.value + p.reading.halfWidth)),
          Offset(cx, y(p.reading.value - p.reading.halfWidth)), whisker);
      final c = Offset(cx, y(p.reading.value));
      if (p.isOutlier) {
        // Hollow diamond: outliers differ by shape, not colour.
        final d = Path()
          ..moveTo(c.dx, c.dy - 6)
          ..lineTo(c.dx + 6, c.dy)
          ..lineTo(c.dx, c.dy + 6)
          ..lineTo(c.dx - 6, c.dy)
          ..close();
        canvas.drawPath(d, ring);
      } else {
        canvas.drawCircle(c, 4, fill);
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.dot != dot || old.line != line;
}
