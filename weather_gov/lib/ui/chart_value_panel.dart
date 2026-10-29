import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/astro_day.dart';
import '../models/hourly_period.dart';
import 'chart_row_entries.dart';

/// The readout strip under the chart: values for the hour under the cursor,
/// one line per visible row group.
class ChartValuePanel extends StatelessWidget {
  final HourlyPeriod period;
  final Map<String, bool> visible;
  final DateTime cursorTime;
  final List<AstroDay> astroDays;
  final bool use24Hour;
  final bool useMetric;

  const ChartValuePanel({
    super.key,
    required this.period,
    required this.visible,
    required this.cursorTime,
    required this.astroDays,
    required this.use24Hour,
    required this.useMetric,
  });

  @override
  Widget build(BuildContext context) {
    final p = period;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final screenWidth = MediaQuery.of(context).size.width;
    final timeFmt = DateFormat(use24Hour ? 'EEE HH:mm' : 'EEE h:mm a');

    // Tabular digits keep values from wobbling as the cursor moves.
    final valueStyle = textTheme.labelMedium!.copyWith(
      fontSize: 16,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

    // Scale factor: base design at 425px → 90% of actual screen width.
    final s = screenWidth * 0.9 / 425;

    // Fixed-width cell. For labeled cells (e.g. "WC 32°F") the label is
    // dropped automatically when the full string won't fit, leaving just
    // the value portion.
    Widget cell(String text, Color color, double width) => SizedBox(
          width: width,
          child: Text(
            text,
            style: valueStyle.copyWith(color: color),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        );

    double measure(String text) => (TextPainter(
          text: TextSpan(text: text, style: valueStyle),
          textDirection: ui.TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: double.infinity))
            .width;

    // Drops label if full text exceeds width.
    String adaptive(String label, String value, double width) {
      return measure('$label $value') <= width ? '$label $value' : value;
    }

    // For line 3: full → initials (multi-word) or first-two (single word) → value only.
    String adaptiveShort(String label, String value, double width) {
      final full = '$label $value';
      if (measure(full) <= width) return full;
      final words = label.split(' ');
      final abbr = words.length > 1
          ? words.map((w) => w.isNotEmpty ? w[0] : '').join()
          : label.substring(0, label.length >= 2 ? 2 : label.length);
      final short = '$abbr:$value';
      if (measure(short) <= width) return short;
      return value;
    }

    // Narrow separator — just 4px of breathing room between cells.
    Widget sep() => SizedBox(
          width: 20,
          child: Text('·',
              textAlign: TextAlign.center,
              style: valueStyle.copyWith(color: scheme.onSurfaceVariant)),
        );

    // Find UV index for the cursor's calendar day.
    final cursorDate = DateTime(cursorTime.year, cursorTime.month, cursorTime.day);
    final uvIndex = astroDays
        .where((d) => d.date.year == cursorDate.year &&
            d.date.month == cursorDate.month &&
            d.date.day == cursorDate.day)
        .firstOrNull
        ?.uvIndex;

    // Line 1: time + temperature group.
    final line1 = <Widget>[];
    line1.add(cell(timeFmt.format(cursorTime), scheme.onSurface, 105 * s));
    if (uvIndex != null) {
      line1.add(sep());
      line1.add(cell('UV $uvIndex', kColorAstroNoon, 44 * s));
    }
    if (visible[kRowTempGroup] == true) {
      String fmtTemp(double f) {
        final v = useMetric ? (f - 32) * 5 / 9 : f;
        return '${v.round()}°${useMetric ? 'C' : 'F'}';
      }
      line1.add(sep());
      line1.add(cell(fmtTemp(p.temperature.toDouble()), adaptiveChartColor(kColorTemperature, brightness), 70 * s));
      line1.add(sep());
      line1.add(cell(adaptive('WC', fmtTemp(p.windChillF), 90 * s), adaptiveChartColor(kColorWindChill, brightness), 90 * s));
      line1.add(sep());
      line1.add(cell(adaptive('Dew', fmtTemp(p.dewpointF), 100 * s), adaptiveChartColor(kColorDewpoint, brightness), 100 * s));
    }

    // Line 2: wind + atmos group.
    final line2 = <Widget>[];
    if (visible[kRowWindGroup] == true) {
      final windVal = useMetric ? (p.windSpeedMph * 1.60934).round() : p.windSpeedMph.round();
      final windUnit = useMetric ? 'km/h' : 'mph';
      line2.add(cell(adaptive('$windVal $windUnit', p.windDirection, 108 * s), adaptiveChartColor(kColorWind, brightness), 108 * s));
    }
    if (visible[kRowAtmosGroup] == true) {
      if (line2.isNotEmpty) line2.add(sep());
      line2.add(cell(adaptive('RH', '${p.relativeHumidity}%', 79 * s), adaptiveChartColor(kColorHumidity, brightness), 79 * s));
      line2.add(sep());
      line2.add(cell(adaptive('Precip', '${p.precipChance}%', 91 * s), adaptiveChartColor(kColorPrecip, brightness), 91 * s));
      line2.add(sep());
      line2.add(cell(adaptive('Sky', '${p.skyCoverPct}%', 87 * s), adaptiveChartColor(kColorSkycover, brightness), 87 * s));
    }

    // Line 3: precip detail group (only when row is visible).
    final line3 = <Widget>[];
    if (visible[kRowPrecipDetail] == true) {
      int covPct(String? c) => switch (c) {
        'slight_chance' => 25, 'chance' => 50, 'likely' => 75, 'definite' => 100, _ => 0
      };
      final wt = p.weatherTypes;
      const rainKeys = {'rain', 'rain_showers'};
      const snowKeys = {'snow', 'snow_showers'};
      const thunderKeys = {'thunderstorms'};
      int rainPct = 0, snowPct = 0, thunderCovPct = 0;
      final otherTypes = <String, int>{};
      if (wt != null) {
        for (final e in wt.entries) {
          final pct = covPct(e.value);
          if (pct == 0) continue;
          if (rainKeys.contains(e.key)) { if (pct > rainPct) rainPct = pct; }
          else if (snowKeys.contains(e.key)) { if (pct > snowPct) snowPct = pct; }
          else if (thunderKeys.contains(e.key)) { if (pct > thunderCovPct) thunderCovPct = pct; }
          else { otherTypes[e.key] = pct; }
        }
      }
      // Use gridpoint thunderPct if available, otherwise fall back to coverage pct.
      final thunderVal = p.thunderPct ?? thunderCovPct;

      // Divide 90% of screen evenly: n cells + (n-1) separators of 20px.
      final n3 = 3 + otherTypes.length;
      final cw3 = (screenWidth * 0.9 - (n3 - 1) * 20) / n3;

      line3.add(cell(adaptiveShort('Rain', '$rainPct%', cw3), kColorPrecip, cw3));
      line3.add(sep());
      line3.add(cell(adaptiveShort('Snow', '$snowPct%', cw3), kColorWeatherSnow, cw3));
      line3.add(sep());
      line3.add(cell(adaptiveShort('Thunder', '$thunderVal%', cw3), kColorWeatherThunder, cw3));
      for (final e in otherTypes.entries) {
        line3.add(sep());
        final typeColor = kPrecipLineTypeColors[e.key] ?? scheme.onSurfaceVariant;
        line3.add(cell(adaptiveShort(precipTypeLabel(e.key), '${e.value}%', cw3), typeColor, cw3));
      }
    }

    Widget buildLine(List<Widget> items) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: screenWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: items,
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: brightness == Brightness.light ? kLightSurface : kDarkSurface,
        border: Border(
          top: BorderSide(color: scheme.outline, width: 1.0),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          buildLine(line1),
          if (line2.isNotEmpty) buildLine(line2),
          if (line3.isNotEmpty) buildLine(line3),
        ],
      ),
    );
  }
}
