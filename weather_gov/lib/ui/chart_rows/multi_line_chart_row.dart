import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';
import '../chart_scale.dart';

class ChartSeries {
  final Color color;
  final double Function(HourlyPeriod) valueSelector;
  const ChartSeries({required this.color, required this.valueSelector});
}

class MultiLineChartRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final List<ChartSeries> series;
  final double? minY;
  final double? maxY;
  final double height;

  const MultiLineChartRow({
    super.key,
    required this.periods,
    required this.series,
    this.minY,
    this.maxY,
    this.height = kChartRowHeight,
  });

  @override
  Widget build(BuildContext context) {
    final gridColor = Theme.of(context).colorScheme.outline.withAlpha(70);
    final scale = ChartScale.of(context);
    final pph = scale.pixelsPerHour;

    // Compute bounds from all series when not provided.
    double lo = minY ?? double.infinity;
    double hi = maxY ?? double.negativeInfinity;
    if (minY == null || maxY == null) {
      for (final s in series) {
        for (final p in periods) {
          final v = s.valueSelector(p);
          if (minY == null && v < lo) lo = v;
          if (maxY == null && v > hi) hi = v;
        }
      }
      if (minY == null) lo = (lo - 4).floorToDouble();
      if (maxY == null) hi = (hi + 4).ceilToDouble();
    }

    final range = hi - lo;
    final hInterval = range > 80
        ? 20.0
        : range > 40
            ? 10.0
            : range > 20
                ? 5.0
                : 2.0;

    final dayBounds = <int>{};
    for (int i = 0; i < periods.length; i++) {
      if (scale.toLocationTime(periods[i].startTime).hour == 0) dayBounds.add(i);
    }

    return SizedBox(
      width: periods.length * pph,
      height: height,
      child: CustomPaint(
        painter: _MultiLinePainter(
          periods: periods,
          series: series,
          minY: lo,
          maxY: hi,
          hInterval: hInterval,
          dayBounds: dayBounds,
          gridColor: gridColor,
          pixelsPerHour: pph,
          tzOffsetHours: scale.tzOffsetHours,
        ),
      ),
    );
  }
}

class _MultiLinePainter extends CustomPainter {
  final List<HourlyPeriod> periods;
  final List<ChartSeries> series;
  final double minY;
  final double maxY;
  final double hInterval;
  final Set<int> dayBounds;
  final Color gridColor;
  final double pixelsPerHour;
  final int tzOffsetHours;

  const _MultiLinePainter({
    required this.periods,
    required this.series,
    required this.minY,
    required this.maxY,
    required this.hInterval,
    required this.dayBounds,
    required this.gridColor,
    required this.pixelsPerHour,
    this.tzOffsetHours = 0,
  });

  double _toCanvasY(double value, double canvasHeight) =>
      canvasHeight * (1.0 - (value - minY) / (maxY - minY));

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = gridColor..strokeWidth = 0.5;

    // Horizontal grid lines.
    double y = minY;
    while (y <= maxY + 1e-9) {
      final cy = _toCanvasY(y, size.height);
      canvas.drawLine(Offset(0, cy), Offset(size.width, cy), gridPaint);
      y += hInterval;
    }

    // Vertical grid lines — zoom-aware.
    final hourStep = chartHourStep(pixelsPerHour);
    for (int i = 0; i < periods.length; i++) {
      final hour = periods[i].startTime.toUtc().add(Duration(hours: tzOffsetHours)).hour;
      if (hour % hourStep != 0) continue;
      final cx = i * pixelsPerHour;
      final isDayBound = dayBounds.contains(i);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, size.height),
        Paint()
          ..color = gridColor
          ..strokeWidth = isDayBound ? 2.5 : 0.5,
      );
    }

    // Draw each series as straight lines.
    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      for (int i = 0; i < periods.length; i++) {
        final cx = i * pixelsPerHour;
        final cy = _toCanvasY(s.valueSelector(periods[i]), size.height);
        if (i == 0) {
          path.moveTo(cx, cy);
        } else {
          path.lineTo(cx, cy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MultiLinePainter old) =>
      old.periods != periods ||
      old.series != series ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.pixelsPerHour != pixelsPerHour;
}
