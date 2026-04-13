import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../constants.dart';
import '../../models/astro_day.dart';
import '../../models/hourly_period.dart';
import '../chart_scale.dart';

String? _svgAssetForPhase(String? phase) {
  switch (phase) {
    case 'New Moon':         return 'assets/moon_phases/new_moon.svg';
    case 'Waxing Crescent':  return 'assets/moon_phases/waxing_crescent.svg';
    case 'First Quarter':    return 'assets/moon_phases/first_quarter.svg';
    case 'Waxing Gibbous':   return 'assets/moon_phases/waxing_gibbous.svg';
    case 'Full Moon':        return 'assets/moon_phases/full_moon.svg';
    case 'Waning Gibbous':   return 'assets/moon_phases/waning_gibbous.svg';
    case 'Last Quarter':     return 'assets/moon_phases/last_quarter.svg';
    case 'Waning Crescent':  return 'assets/moon_phases/waning_crescent.svg';
    default: return null;
  }
}

class AstroRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final List<AstroDay> astroDays;
  final double height;
  final bool showSolar;
  final bool showLunar;

  const AstroRow({
    super.key,
    required this.periods,
    required this.astroDays,
    this.height = 50.0,
    this.showSolar = true,
    this.showLunar = true,
  });

  @override
  Widget build(BuildContext context) {
    final scale = ChartScale.of(context);
    final pph = scale.pixelsPerHour;
    final totalWidth = periods.length * pph;
    final windowStart = scale.toLocationTime(periods.first.startTime);
    final frameColor = Theme.of(context).colorScheme.outline.withAlpha(120);

    // When both bands are shown, each takes half the height.
    // When only one is shown, it occupies the full height.
    final both = showSolar && showLunar;
    final moonBandTop    = both ? height / 2 : 0.0;
    final moonBandHeight = both ? height / 2 : height;

    double xFor(DateTime dt) {
      final minutes = dt.difference(windowStart).inMinutes;
      return (minutes / 60.0) * pph;
    }

    // Build moon phase icon overlays centered between moonrise and moonset.
    final moonIcons = <Widget>[];
    if (showLunar) {
      for (final day in astroDays) {
        if (day.isSentinel) continue;
        final asset = _svgAssetForPhase(day.moonPhase);
        if (asset == null) continue;
        final rise = day.moonrise;
        final set = day.moonset;
        if (rise == null && set == null) continue;

        // Center x: midpoint of visible moon-up segment, clamped to total width.
        double centerX;
        if (rise != null && set != null && set.isAfter(rise)) {
          centerX = (xFor(rise) + xFor(set)) / 2;
        } else if (rise != null) {
          // Rises today, sets tomorrow — center in second half of day.
          final dayEnd = DateTime(day.date.year, day.date.month, day.date.day + 1);
          centerX = (xFor(rise) + xFor(dayEnd)) / 2;
        } else {
          // Sets today, rose yesterday — center in first half.
          centerX = (0 + xFor(set!)) / 2;
        }
        centerX = centerX.clamp(0.0, totalWidth);

        const iconSize = 18.0;
        moonIcons.add(Positioned(
          left: centerX - iconSize / 2,
          top: moonBandTop + (moonBandHeight - iconSize) / 2,
          width: iconSize,
          height: iconSize,
          child: SvgPicture.asset(asset),
        ));
      }
    }

    return SizedBox(
      width: totalWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          CustomPaint(
            size: Size(totalWidth, height),
            painter: _AstroPainter(
              periods: periods,
              astroDays: astroDays,
              height: height,
              pixelsPerHour: pph,
              tzOffsetHours: scale.tzOffsetHours,
              showSolar: showSolar,
              showLunar: showLunar,
              frameColor: frameColor,
            ),
          ),
          ...moonIcons,
        ],
      ),
    );
  }
}

class _AstroPainter extends CustomPainter {
  final List<HourlyPeriod> periods;
  final List<AstroDay> astroDays;
  final double height;
  final double pixelsPerHour;
  final bool showSolar;
  final bool showLunar;
  final int tzOffsetHours;
  final Color frameColor;

  const _AstroPainter({
    required this.periods,
    required this.astroDays,
    required this.height,
    required this.pixelsPerHour,
    required this.frameColor,
    this.showSolar = true,
    this.showLunar = true,
    this.tzOffsetHours = 0,
  });

  DateTime _toLocationTime(DateTime dt) =>
      dt.toUtc().add(Duration(hours: tzOffsetHours));

  DateTime get _windowStart => _toLocationTime(periods.first.startTime);

  double _xFor(DateTime dt) {
    final minutes = dt.difference(_windowStart).inMinutes;
    return (minutes / 60.0) * pixelsPerHour;
  }

  double _xClamped(DateTime dt, double totalWidth) =>
      _xFor(dt).clamp(0.0, totalWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final both = showSolar && showLunar;
    final sunHeight = both ? size.height / 2 : (showSolar ? size.height : 0.0);
    final moonTop   = both ? sunHeight : 0.0;
    final moonHeight = both ? size.height / 2 : (showLunar ? size.height : 0.0);
    final totalWidth = size.width;

    // Base fill: night color.
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
      if (showSolar) {
      _fillSegment(canvas, day.beginCivilTwilight, day.sunrise,
          kColorAstroCivilTwilight, 0, sunHeight, totalWidth);
      _fillSegment(canvas, day.sunrise, day.sunset,
          kColorAstroDay, 0, sunHeight, totalWidth);
      _fillSegment(canvas, day.sunset, day.endCivilTwilight,
          kColorAstroCivilTwilight, 0, sunHeight, totalWidth);
      }

      // Noon marker — 3px wide, full sun-band height.
      if (showSolar && day.solarNoon != null) {
        final nx = _xFor(day.solarNoon!);
        if (nx >= 0 && nx <= totalWidth) {
          canvas.drawRect(
            Rect.fromLTWH(nx - 1.5, 0, 3, sunHeight),
            Paint()..color = kColorAstroNoon,
          );

          // UV index label: "UV" left of marker, number right of marker.
          if (day.uvIndex != null) {
            const fontSize = 9.0;
            const gap = 3.0;
            final textStyle = TextStyle(
              color: kColorAstroNoon,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            );

            void drawLabel(String text, {required bool leftOfMarker}) {
              final tp = TextPainter(
                text: TextSpan(text: text, style: textStyle),
                textDirection: TextDirection.ltr,
              )..layout();
              final dy = (sunHeight - tp.height) / 2;
              final dx = leftOfMarker
                  ? nx - 1.5 - gap - tp.width
                  : nx + 1.5 + gap;
              tp.paint(canvas, Offset(dx, dy));
            }

            drawLabel('UV', leftOfMarker: true);
            drawLabel('${day.uvIndex}', leftOfMarker: false);
          }
        }
      }
    }

    // Moon band.
    if (showLunar) _paintMoonBand(canvas, moonTop, moonHeight, totalWidth);

    // Top and bottom frame lines.
    final framePaint = Paint()
      ..color = frameColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, 0), Offset(totalWidth, 0), framePaint);
    canvas.drawLine(Offset(0, size.height), Offset(totalWidth, size.height), framePaint);
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
      old.height != height ||
      old.pixelsPerHour != pixelsPerHour ||
      old.showSolar != showSolar ||
      old.showLunar != showLunar ||
      old.tzOffsetHours != tzOffsetHours;
}
