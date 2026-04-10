import 'dart:math';
import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';
import '../chart_scale.dart';

// Cardinal direction → degrees FROM which wind blows (met convention).
const _dirDeg = <String, double>{
  'N': 0,   'NNE': 22.5, 'NE': 45,  'ENE': 67.5,
  'E': 90,  'ESE': 112.5,'SE': 135, 'SSE': 157.5,
  'S': 180, 'SSW': 202.5,'SW': 225, 'WSW': 247.5,
  'W': 270, 'WNW': 292.5,'NW': 315, 'NNW': 337.5,
};

class WindBarbRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final double height;
  final double minY;
  final double maxY;
  final double hInterval;

  const WindBarbRow({
    super.key,
    required this.periods,
    required this.minY,
    required this.maxY,
    required this.hInterval,
    this.height = kChartRowHeight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final pph = ChartScale.of(context).pixelsPerHour;
    return SizedBox(
      width: periods.length * pph,
      height: height,
      child: CustomPaint(
        painter: _WindBarbPainter(
          periods: periods,
          lineColor: adaptiveChartColor(kColorWind, brightness),
          barbColor: scheme.outline,
          gridColor: scheme.outline.withAlpha(70),
          minY: minY,
          maxY: maxY,
          hInterval: hInterval,
          pixelsPerHour: pph,
        ),
      ),
    );
  }
}

class _WindBarbPainter extends CustomPainter {
  final List<HourlyPeriod> periods;
  final Color lineColor;
  final Color barbColor;
  final Color gridColor;
  final double minY;
  final double maxY;
  final double hInterval;
  final double pixelsPerHour;

  const _WindBarbPainter({
    required this.periods,
    required this.lineColor,
    required this.barbColor,
    required this.gridColor,
    required this.minY,
    required this.maxY,
    required this.hInterval,
    required this.pixelsPerHour,
  });

  double _yForSpeed(double speed, double height) {
    return height * (1.0 - (speed - minY) / (maxY - minY));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Horizontal grid lines at hInterval increments.
    final first = (minY / hInterval).ceil() * hInterval;
    for (double v = first; v <= maxY + 0.001; v += hInterval) {
      final y = _yForSpeed(v, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical lines — density scales with zoom.
    final hourStep = chartHourStep(pixelsPerHour);
    for (int i = 0; i < periods.length; i++) {
      final hour = periods[i].startTime.toLocal().hour;
      if (hour % hourStep != 0) continue;
      final x = i * pixelsPerHour;
      final isDayBoundary = hour == 0;
      gridPaint.strokeWidth = isDayBoundary ? 2.5 : 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Straight connecting line through barb centers.
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final pts = List.generate(periods.length, (i) => Offset(
      i * pixelsPerHour,
      _yForSpeed(periods[i].windSpeedMph, size.height),
    ));
    if (pts.isNotEmpty) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // Draw each wind barb at the y position corresponding to wind speed.
    for (int i = 0; i < periods.length; i++) {
      final speed = periods[i].windSpeedMph;
      final cx = i * pixelsPerHour;
      final cy = _yForSpeed(speed, size.height);
      _drawBarb(
        canvas,
        Offset(cx, cy),
        speed,
        _dirDeg[periods[i].windDirection] ?? 0,
      );
    }
  }

  void _drawBarb(
      Canvas canvas, Offset center, double speedMph, double dirDeg) {
    final dimColor = barbColor.withAlpha(80);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = dimColor
      ..style = PaintingStyle.fill;

    // Calm wind: draw a small circle and return.
    if (speedMph < 2.5) {
      canvas.drawCircle(center, 3.5, linePaint);
      return;
    }

    // Round to nearest 5 knots (minimum 5).
    final int kt = max(5, ((speedMph * 0.869) / 5).round() * 5);

    // Staff direction unit vector (points FROM center toward "from" direction).
    // Met convention: 0° = N, 90° = E, positive clockwise.
    // Screen: y-axis points DOWN.  N = (0,-1), E = (1,0), S = (0,1), W = (-1,0).
    final rad = dirDeg * pi / 180;
    final sDx = sin(rad);
    final sDy = -cos(rad);

    // Barb perpendicular: rotated 90° CW from staff in screen coords = (-sDy, sDx).
    // For N wind (sDx=0, sDy=-1): barb = (1, 0) = east. Correct per met convention.
    final bDx = -sDy;
    final bDy = sDx;

    const staffLen = 20.0;
    const fullBarb = 9.0;
    const halfBarb = 4.5;
    const pennantW = 9.0;
    const spacing = 3.5;

    final tip =
        Offset(center.dx + sDx * staffLen, center.dy + sDy * staffLen);

    // Draw staff.
    canvas.drawLine(center, tip, linePaint);

    int remaining = kt;
    double pos = 0; // distance from tip along staff toward base

    // Pennants (50 kt each).
    while (remaining >= 50) {
      final p0 = Offset(tip.dx - sDx * pos, tip.dy - sDy * pos);
      final p1 =
          Offset(p0.dx + bDx * pennantW, p0.dy + bDy * pennantW);
      final p2 = Offset(
          tip.dx - sDx * (pos + spacing * 2),
          tip.dy - sDy * (pos + spacing * 2));
      canvas.drawPath(
          Path()
            ..moveTo(p0.dx, p0.dy)
            ..lineTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..close(),
          fillPaint);
      remaining -= 50;
      pos += spacing * 2 + spacing * 0.5;
    }

    // Full barbs (10 kt each).
    while (remaining >= 10) {
      final p0 = Offset(tip.dx - sDx * pos, tip.dy - sDy * pos);
      final p1 = Offset(p0.dx + bDx * fullBarb, p0.dy + bDy * fullBarb);
      canvas.drawLine(p0, p1, linePaint);
      remaining -= 10;
      pos += spacing;
    }

    // Half barb (5 kt).
    if (remaining >= 5) {
      // If no other barbs drawn, offset slightly from tip.
      if (pos == 0) pos = spacing;
      final p0 = Offset(tip.dx - sDx * pos, tip.dy - sDy * pos);
      final p1 = Offset(p0.dx + bDx * halfBarb, p0.dy + bDy * halfBarb);
      canvas.drawLine(p0, p1, linePaint);
    }
  }

  @override
  bool shouldRepaint(_WindBarbPainter old) =>
      old.periods != periods ||
      old.lineColor != lineColor ||
      old.barbColor != barbColor ||
      old.gridColor != gridColor ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.hInterval != hInterval;
}
