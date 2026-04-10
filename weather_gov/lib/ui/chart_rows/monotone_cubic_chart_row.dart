import 'dart:math' show sqrt;
import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';
import '../chart_scale.dart';
import 'multi_line_chart_row.dart';

/// Renders chart lines using monotone cubic interpolation (Fritsch-Carlson).
/// Guarantees no oscillation / wiggles on steadily increasing or decreasing data.
///
/// Set [showGrid] to false to draw only the lines (for overlaying on top of
/// another chart row that already draws the grid).
class MonotoneCubicChartRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final List<ChartSeries> series;
  final double minY;
  final double maxY;
  final double height;
  final bool showGrid;

  const MonotoneCubicChartRow({
    super.key,
    required this.periods,
    required this.series,
    required this.minY,
    required this.maxY,
    this.height = kChartRowHeight,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    final gridColor = Theme.of(context).colorScheme.outline.withAlpha(70);
    final pph = ChartScale.of(context).pixelsPerHour;

    final range = maxY - minY;
    final hInterval = range > 80
        ? 20.0
        : range > 40
            ? 10.0
            : range > 20
                ? 5.0
                : 2.0;

    final dayBounds = <int>{};
    for (int i = 0; i < periods.length; i++) {
      if (periods[i].startTime.toLocal().hour == 0) dayBounds.add(i);
    }

    return SizedBox(
      width: periods.length * pph,
      height: height,
      child: CustomPaint(
        painter: _MonotoneCubicPainter(
          periods: periods,
          series: series,
          minY: minY,
          maxY: maxY,
          hInterval: hInterval,
          dayBounds: dayBounds,
          gridColor: gridColor,
          showGrid: showGrid,
          pixelsPerHour: pph,
        ),
      ),
    );
  }
}

class _MonotoneCubicPainter extends CustomPainter {
  final List<HourlyPeriod> periods;
  final List<ChartSeries> series;
  final double minY;
  final double maxY;
  final double hInterval;
  final Set<int> dayBounds;
  final Color gridColor;
  final bool showGrid;
  final double pixelsPerHour;

  const _MonotoneCubicPainter({
    required this.periods,
    required this.series,
    required this.minY,
    required this.maxY,
    required this.hInterval,
    required this.dayBounds,
    required this.gridColor,
    required this.showGrid,
    required this.pixelsPerHour,
  });

  double _toCanvasY(double value, double canvasHeight) {
    return canvasHeight * (1.0 - (value - minY) / (maxY - minY));
  }

  double _toCanvasX(int index) => index * pixelsPerHour;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) _drawGrid(canvas, size);
    for (final s in series) {
      _drawMonotoneCubic(canvas, size, s);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    double y = minY;
    while (y <= maxY + 1e-9) {
      final cy = _toCanvasY(y, size.height);
      canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
      y += hInterval;
    }

    final hourStep = chartHourStep(pixelsPerHour);
    for (int i = 0; i < periods.length; i++) {
      final hour = periods[i].startTime.toLocal().hour;
      if (hour % hourStep != 0) continue;
      final cx = _toCanvasX(i);
      final isDayBound = dayBounds.contains(i);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, size.height),
        Paint()
          ..color = gridColor
          ..strokeWidth = isDayBound ? 2.5 : 0.5,
      );
    }
  }

  void _drawMonotoneCubic(Canvas canvas, Size size, ChartSeries s) {
    final n = periods.length;
    if (n < 2) return;

    final xs = List<double>.generate(n, (i) => _toCanvasX(i));
    final ys = List<double>.generate(
        n, (i) => _toCanvasY(s.valueSelector(periods[i]), size.height));

    final delta = List<double>.filled(n - 1, 0.0);
    for (int i = 0; i < n - 1; i++) {
      delta[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]);
    }

    final m = List<double>.filled(n, 0.0);
    m[0] = delta[0];
    m[n - 1] = delta[n - 2];
    for (int i = 1; i < n - 1; i++) {
      m[i] = (delta[i - 1] + delta[i]) / 2.0;
    }

    for (int i = 0; i < n - 1; i++) {
      if (delta[i] == 0.0) {
        m[i] = 0.0;
        m[i + 1] = 0.0;
      } else {
        final alpha = m[i] / delta[i];
        final beta = m[i + 1] / delta[i];
        final h = alpha * alpha + beta * beta;
        if (h > 9.0) {
          final tau = 3.0 / sqrt(h);
          m[i] = tau * alpha * delta[i];
          m[i + 1] = tau * beta * delta[i];
        }
      }
    }

    final path = Path()..moveTo(xs[0], ys[0]);
    for (int i = 0; i < n - 1; i++) {
      final dx = (xs[i + 1] - xs[i]) / 3.0;
      path.cubicTo(
        xs[i] + dx,     ys[i] + m[i] * dx,
        xs[i + 1] - dx, ys[i + 1] - m[i + 1] * dx,
        xs[i + 1],      ys[i + 1],
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MonotoneCubicPainter old) =>
      old.periods != periods ||
      old.series != series ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.pixelsPerHour != pixelsPerHour;
}
