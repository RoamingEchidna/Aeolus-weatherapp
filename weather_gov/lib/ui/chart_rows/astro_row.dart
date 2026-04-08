import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/astro_day.dart';
import '../../models/hourly_period.dart';

class AstroRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final List<AstroDay> astroDays;
  final double height;

  const AstroRow({
    super.key,
    required this.periods,
    required this.astroDays,
    this.height = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: periods.length * kPixelsPerHour,
      height: height,
      child: CustomPaint(
        painter: _AstroPainter(
          periods: periods,
          astroDays: astroDays,
          height: height,
        ),
      ),
    );
  }
}

class _AstroPainter extends CustomPainter {
  final List<HourlyPeriod> periods;
  final List<AstroDay> astroDays;
  final double height;

  const _AstroPainter({
    required this.periods,
    required this.astroDays,
    required this.height,
  });

  DateTime get _windowStart => periods.first.startTime.toLocal();

  double _xFor(DateTime dt) {
    final minutes = dt.difference(_windowStart).inMinutes;
    return (minutes / 60.0) * kPixelsPerHour;
  }

  double _xClamped(DateTime dt, double totalWidth) =>
      _xFor(dt).clamp(0.0, totalWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final sunHeight = size.height / 2; // top 25dp
    final moonTop   = sunHeight;       // bottom 25dp
    final totalWidth = size.width;

    // Base fill: night color for both bands.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, totalWidth, size.height),
      Paint()..color = kColorAstroNight,
    );

    for (final day in astroDays) {
      if (day.isSentinel) {
        _drawHatching(canvas, day, totalWidth, size.height);
        continue;
      }

      // Sun band.
      _fillSegment(canvas, day.beginCivilTwilight, day.sunrise,
          kColorAstroCivilTwilight, 0, sunHeight, totalWidth);
      _fillSegment(canvas, day.sunrise, day.sunset,
          kColorAstroDay, 0, sunHeight, totalWidth);
      _fillSegment(canvas, day.sunset, day.endCivilTwilight,
          kColorAstroCivilTwilight, 0, sunHeight, totalWidth);

      // Noon marker — 3px wide, full sun-band height.
      if (day.solarNoon != null) {
        final nx = _xFor(day.solarNoon!);
        if (nx >= 0 && nx <= totalWidth) {
          canvas.drawRect(
            Rect.fromLTWH(nx - 1.5, 0, 3, sunHeight),
            Paint()..color = kColorAstroNoon,
          );
        }
      }
    }

    // Moon band.
    _paintMoonBand(canvas, moonTop, sunHeight, totalWidth);
  }

  void _fillSegment(Canvas canvas, DateTime? start, DateTime? end,
      Color color, double top, double height, double totalWidth) {
    if (start == null || end == null) return;
    final x0 = _xClamped(start, totalWidth);
    final x1 = _xClamped(end, totalWidth);
    if (x1 <= x0) return;
    canvas.drawRect(
      Rect.fromLTWH(x0, top, x1 - x0, height),
      Paint()..color = color,
    );
  }

  void _paintMoonBand(
      Canvas canvas, double top, double height, double totalWidth) {
    final moonPaint = Paint()..color = kColorAstroMoonUp;

    for (int i = 0; i < astroDays.length; i++) {
      final day = astroDays[i];
      if (day.isSentinel) continue;

      final rise = day.moonrise;
      final set  = day.moonset;

      if (rise == null && set == null) continue;

      if (rise != null && set != null) {
        if (set.isAfter(rise)) {
          // Normal same-day arc.
          final x0 = _xClamped(rise, totalWidth);
          final x1 = _xClamped(set, totalWidth);
          if (x1 > x0) {
            canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
          }
        } else {
          // set <= rise: moon set early this day (rose yesterday).
          // Paint midnight-to-set portion.
          final x0 = _xClamped(day.date, totalWidth);
          final x1 = _xClamped(set, totalWidth);
          if (x1 > x0) {
            canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
          }
          // Paint rise-to-end-of-day from the previous day.
          if (i > 0 && !astroDays[i - 1].isSentinel) {
            final prevRise = astroDays[i - 1].moonrise;
            if (prevRise != null) {
              final dayEndX = _xClamped(
                DateTime(day.date.year, day.date.month, day.date.day, 23, 59, 59),
                totalWidth,
              );
              final px0 = _xClamped(prevRise, totalWidth);
              if (dayEndX > px0) {
                canvas.drawRect(
                    Rect.fromLTWH(px0, top, dayEndX - px0, height), moonPaint);
              }
            }
          }
        }
      } else if (rise != null) {
        // Moon rises today, sets tomorrow — paint rise to end of day.
        final dayEnd = DateTime(day.date.year, day.date.month, day.date.day + 1);
        final x0 = _xClamped(rise, totalWidth);
        final x1 = _xClamped(dayEnd, totalWidth);
        if (x1 > x0) {
          canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
        }
      } else {
        // set != null, rise == null: moon already up at midnight, sets today.
        final x0 = _xClamped(day.date, totalWidth);
        final x1 = _xClamped(set!, totalWidth);
        if (x1 > x0) {
          canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
        }
      }
    }
  }

  void _drawHatching(
      Canvas canvas, AstroDay day, double totalWidth, double fullHeight) {
    final x0 = _xClamped(day.date, totalWidth);
    final x1 = _xClamped(
      DateTime(day.date.year, day.date.month, day.date.day + 1),
      totalWidth,
    );
    if (x1 <= x0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(x0, 0, x1 - x0, fullHeight));

    const spacing = 6.0;
    final p1 = Paint()
      ..color = kColorAstroNight
      ..strokeWidth = spacing / 2
      ..style = PaintingStyle.stroke;
    final p2 = Paint()
      ..color = kColorAstroCivilTwilight
      ..strokeWidth = spacing / 2
      ..style = PaintingStyle.stroke;

    int lineIndex = 0;
    for (double offset = -fullHeight; offset < (x1 - x0) + fullHeight; offset += spacing) {
      final paint = lineIndex.isEven ? p1 : p2;
      canvas.drawLine(
        Offset(x0 + offset, 0),
        Offset(x0 + offset + fullHeight, fullHeight),
        paint,
      );
      lineIndex++;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AstroPainter old) =>
      old.periods != periods ||
      old.astroDays != astroDays ||
      old.height != height;
}
