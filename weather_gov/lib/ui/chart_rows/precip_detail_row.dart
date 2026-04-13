import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';
import '../chart_scale.dart';

// Coverage string → likelihood percentage (0 if not a recognised coverage).
double _covToPct(String? cov) {
  switch (cov) {
    case 'slight_chance': return 25;
    case 'chance':        return 50;
    case 'likely':        return 75;
    case 'definite':      return 100;
    default:              return 0;
  }
}

// Best coverage for a set of type keys within a weatherTypes map.
double _bestCov(Map<String, String>? types, Set<String> keys) {
  if (types == null) return 0;
  double best = 0;
  for (final k in keys) {
    final v = _covToPct(types[k]);
    if (v > best) best = v;
  }
  return best;
}

const _kRainTypes    = {'rain', 'rain_showers'};
const _kSnowTypes    = {'snow', 'snow_showers'};

// Colors for "other" weather types shown as line graphs.
const _kLineTypeColors = <String, Color>{
  'freezing_rain':    kColorWeatherFreezingRain,
  'freezing_drizzle': Color(0xFFBBAACE),
  'ice_pellets':      kColorWeatherSleet,
  'sleet':            kColorWeatherSleet,
  'blizzard':         Color(0xFFAADDFF),
  'fog':              Color(0xFFB0BEC5),
  'ice_fog':          Color(0xFFB0BEC5),
  'freezing_fog':     Color(0xFF90A4AE),
  'haze':             Color(0xFFD4B896),
  'smoke':            Color(0xFF9E9E9E),
  'dust':             Color(0xFFD4A96A),
  'sand':             Color(0xFFD4A96A),
  'volcanic_ash':     Color(0xFF78909C),
  'water_spouts':     Color(0xFF4FC3F7),
  'tornadoes':        Color(0xFFEF5350),
};

class PrecipDetailRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final double height;

  const PrecipDetailRow({
    super.key,
    required this.periods,
    this.height = kChartRowHeight,
  });

  @override
  Widget build(BuildContext context) {
    final scale     = ChartScale.of(context);
    final pph       = scale.pixelsPerHour;
    final gridColor = Theme.of(context).colorScheme.outline.withAlpha(70);
    final brightness = Theme.of(context).brightness;

    // Detect which "line" types appear in the entire dataset.
    final presentLineTypes = <String>{};
    for (final p in periods) {
      if (p.weatherTypes == null) continue;
      for (final t in p.weatherTypes!.keys) {
        if (!_kRainTypes.contains(t) && !_kSnowTypes.contains(t) &&
            t != 'thunderstorms' && _kLineTypeColors.containsKey(t)) {
          presentLineTypes.add(t);
        }
      }
    }

    return SizedBox(
      width: periods.length * pph,
      height: height,
      child: CustomPaint(
        painter: _PrecipDetailPainter(
          periods: periods,
          pixelsPerHour: pph,
          tzOffsetHours: scale.tzOffsetHours,
          gridColor: gridColor,
          presentLineTypes: presentLineTypes,
          brightness: brightness,
        ),
      ),
    );
  }
}

class _PrecipDetailPainter extends CustomPainter {
  final List<HourlyPeriod> periods;
  final double pixelsPerHour;
  final int tzOffsetHours;
  final Color gridColor;
  final Set<String> presentLineTypes;
  final Brightness brightness;

  const _PrecipDetailPainter({
    required this.periods,
    required this.pixelsPerHour,
    required this.tzOffsetHours,
    required this.gridColor,
    required this.presentLineTypes,
    required this.brightness,
  });

  double _yForPct(double h, double pct) => h * (1.0 - pct / 100.0);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final gridPaint = Paint()..color = gridColor..strokeWidth = 0.5;

    // --- Vertical grid lines (day boundaries + hour step) ---
    final hourStep = chartHourStep(pixelsPerHour);
    for (int i = 0; i < periods.length; i++) {
      final locHour = periods[i].startTime.toUtc()
          .add(Duration(hours: tzOffsetHours)).hour;
      if (locHour % hourStep != 0) continue;
      final isDayBound = locHour == 0;
      canvas.drawLine(
        Offset(i * pixelsPerHour, 0),
        Offset(i * pixelsPerHour, h),
        Paint()
          ..color = gridColor
          ..strokeWidth = isDayBound ? 2.5 : 0.5,
      );
    }

    // --- Horizontal grid lines at 25 / 50 / 75 / 100 % ---
    for (final pct in [25.0, 50.0, 75.0, 100.0]) {
      final y = _yForPct(h, pct);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // --- Bars for rain / snow / thunder per hour ---
    for (int i = 0; i < periods.length; i++) {
      final p   = periods[i];
      final x   = i * pixelsPerHour;
      final wt  = p.weatherTypes;

      final rainPct    = _bestCov(wt, _kRainTypes);
      final snowPct    = _bestCov(wt, _kSnowTypes);
      final thunderPct = (p.thunderPct ?? 0).toDouble();

      // Build ordered list: rain, snow, thunder (only present ones).
      final bars = <(double pct, Color color)>[];
      if (rainPct    > 0) bars.add((rainPct,    kColorPrecip));
      if (snowPct    > 0) bars.add((snowPct,    kColorWeatherSnow));
      if (thunderPct > 0) bars.add((thunderPct, kColorWeatherThunder));
      if (bars.isEmpty) continue;

      final barW = pixelsPerHour / bars.length;
      for (int j = 0; j < bars.length; j++) {
        final (pct, color) = bars[j];
        final barH = h * pct / 100.0;
        canvas.drawRect(
          Rect.fromLTWH(x + j * barW, h - barH, barW, barH),
          Paint()..color = color.withAlpha(200),
        );
      }
    }

    // --- Line graphs for other weather types ---
    for (final type in presentLineTypes) {
      final color = _kLineTypeColors[type] ?? Colors.grey;
      final path = Path();
      bool started = false;
      for (int i = 0; i < periods.length; i++) {
        final pct = _covToPct(periods[i].weatherTypes?[type]);
        if (pct <= 0) {
          started = false;
          continue;
        }
        final cx = i * pixelsPerHour + pixelsPerHour / 2;
        final cy = _yForPct(h, pct);
        if (!started) {
          path.moveTo(cx, cy);
          started = true;
        } else {
          path.lineTo(cx, cy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // ignore: unused_element
  void _draw6hAccum(Canvas canvas, Size size) {
    // Build 6h windows aligned to location-time hours divisible by 6.
    // Key: windowStartIndex in periods list.
    final Map<int, ({double rainIn, double snowIn})> windows = {};
    int? windowStart;
    double rainAcc = 0;
    double snowAcc = 0;

    void flush(int endIdx) {
      if (windowStart != null && (rainAcc > 0.005 || snowAcc > 0.005)) {
        windows[windowStart!] = (rainIn: rainAcc, snowIn: snowAcc);
      }
      windowStart = null;
      rainAcc = 0;
      snowAcc = 0;
    }

    for (int i = 0; i < periods.length; i++) {
      final locHour = periods[i].startTime.toUtc()
          .add(Duration(hours: tzOffsetHours)).hour;
      if (locHour % 6 == 0) {
        flush(i);
        windowStart = i;
      }
      if (windowStart != null) {
        rainAcc += periods[i].rainInches ?? 0;
        snowAcc += periods[i].snowInches ?? 0;
      }
    }
    flush(periods.length);

    const boxH = 13.0;
    const labelStyle = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    for (final entry in windows.entries) {
      final startIdx = entry.key;
      final endIdx   = (startIdx + 6).clamp(0, periods.length);
      final left     = startIdx * pixelsPerHour;
      final boxW     = (endIdx - startIdx) * pixelsPerHour;

      double yOff = 0;

      void drawBox(double inches, Color color) {
        final rect = Rect.fromLTWH(left + 1, yOff + 1, boxW - 2, boxH - 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = color.withAlpha(220),
        );
        final label = '${inches.toStringAsFixed(2)}"';
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: boxW - 4);
        tp.paint(canvas,
            Offset(left + (boxW - tp.width) / 2, yOff + (boxH - tp.height) / 2));
        yOff += boxH;
      }

      if (entry.value.rainIn > 0.005) drawBox(entry.value.rainIn, kColorPrecip);
      if (entry.value.snowIn > 0.005) drawBox(entry.value.snowIn, kColorWeatherSnow);
    }
  }

  @override
  bool shouldRepaint(_PrecipDetailPainter old) =>
      old.periods != periods ||
      old.pixelsPerHour != pixelsPerHour ||
      old.tzOffsetHours != tzOffsetHours;
}
