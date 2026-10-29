import 'dart:math';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/astro_day.dart';
import '../models/hourly_period.dart';
import 'chart_rows/multi_line_chart_row.dart';
import 'chart_rows/monotone_cubic_chart_row.dart';
import 'chart_rows/wind_barb_row.dart';
import 'chart_rows/conditions_row.dart';
import 'chart_rows/precip_detail_row.dart';
import 'chart_rows/astro_row.dart';

const Map<String, Color> kPrecipLineTypeColors = {
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

/// 'freezing_rain' → 'Freezing Rain'.
String precipTypeLabel(String key) =>
    key.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

const double _kValuePanelHeight = 64.0;

// Carries a chart row widget plus optional y-axis scale and legend info.
class ChartRowEntry {
  final String name;
  final Widget widget;
  final double height;
  // Null for rows without a numeric y-axis (Conditions).
  final double? minY;
  final double? maxY;
  final double? hInterval;
  final String unit;
  // Empty for rows without a color legend (Conditions).
  final List<({Color color, String label})> legendItems;
  final bool hideEndLabels;

  const ChartRowEntry({
    required this.name,
    required this.widget,
    required this.height,
    this.minY,
    this.maxY,
    this.hInterval,
    this.unit = '',
    this.legendItems = const [],
    this.hideEndLabels = false,
  });
}

// Matches the hInterval logic in MultiLineChartRow so labels align with grid lines.
double _hInterval(double lo, double hi) {
  final range = hi - lo;
  return range > 80 ? 20.0 : range > 40 ? 10.0 : range > 20 ? 5.0 : 2.0;
}

/// Splits [maxHeight] between the rows. Only scaled rows (temp/wind/atmos/
/// precip detail) flex; Conditions stays at 50dp and the astro rows get a
/// slice of the provisional row height.
({double rowHeight, double astroHeight, double valuePanelHeight})
    computeRowHeights(Map<String, bool> visible, double maxHeight) {
  final hasTemp  = visible[kRowTempGroup]  == true;
  final hasWind  = visible[kRowWindGroup]  == true;
  final hasAtmos = visible[kRowAtmosGroup] == true;
  final hasCond        = visible[kRowConditions]   == true;
  final hasPrecipDetail = visible[kRowPrecipDetail] == true;
  final valuePanelHeight = hasPrecipDetail ? 88.0 : _kValuePanelHeight;
  final hasSolar       = visible[kRowSolar]         == true;
  final hasLunar       = visible[kRowLunar]         == true;
  final scaledRowCount = [hasTemp, hasWind, hasAtmos, hasPrecipDetail].where((v) => v).length;
  // Estimate astroHeight using a provisional rowHeight so we can compute fixedHeight.
  double provisionalRowHeight = scaledRowCount == 0
      ? 80.0
      : ((maxHeight - valuePanelHeight - kTimeAxisHeight -
              (hasCond ? 50.0 : 0.0)) /
          scaledRowCount)
          .floorToDouble()
          .clamp(kMinChartRowHeight, 200.0);
  final astroHeight = (provisionalRowHeight * 0.15).clamp(20.0, 50.0);
  final fixedHeight = (hasCond  ? 50.0        : 0.0) +
                      (hasSolar ? astroHeight  : 0.0) +
                      (hasLunar ? astroHeight  : 0.0);
  final rowHeight = scaledRowCount == 0
      ? 80.0
      : ((maxHeight - valuePanelHeight - kTimeAxisHeight -
              fixedHeight) /
          scaledRowCount)
          .floorToDouble()
          .clamp(kMinChartRowHeight, 200.0);
  return (
    rowHeight: rowHeight,
    astroHeight: astroHeight,
    valuePanelHeight: valuePanelHeight,
  );
}

/// Builds the visible rows in [rowOrder].
List<ChartRowEntry> buildChartRows({
  required List<HourlyPeriod> periods,
  required Map<String, bool> visible,
  required List<String> rowOrder,
  required double rowHeight,
  required double astroHeight,
  required List<AstroDay> astroDays,
  required Brightness brightness,
  required bool useMetric,
}) {
  final map = <String, ChartRowEntry>{};

  double toTemp(double f) => useMetric ? (f - 32) * 5 / 9 : f;
  double toWind(double mph) => useMetric ? mph * 1.60934 : mph;

  // --- Temperature / Wind Chill / Dewpoint ---
  if (visible[kRowTempGroup] == true) {
    final allTemps = periods.expand((p) => [
          toTemp(p.temperature.toDouble()),
          toTemp(p.windChillF),
          toTemp(p.dewpointF),
        ]);
    final lo = allTemps.reduce(min);
    final hi = allTemps.reduce(max);
    final minY = (lo - 4).floorToDouble();
    final maxY = (hi + 4).ceilToDouble();
    map[kRowTempGroup] = ChartRowEntry(
      name: kRowTempGroup,
      height: rowHeight,
      minY: minY,
      maxY: maxY,
      hInterval: _hInterval(minY, maxY),
      unit: useMetric ? '°C' : '°F',
      legendItems: [
        (color: adaptiveChartColor(kColorTemperature, brightness), label: 'Temp'),
        (color: adaptiveChartColor(kColorWindChill, brightness), label: 'Wind Chill'),
        (color: adaptiveChartColor(kColorDewpoint, brightness), label: 'Dewpoint'),
      ],
      widget: MonotoneCubicChartRow(
        periods: periods,
        height: rowHeight,
        series: [
          ChartSeries(
              color: adaptiveChartColor(kColorDewpoint, brightness), valueSelector: (p) => toTemp(p.dewpointF)),
          ChartSeries(
              color: adaptiveChartColor(kColorWindChill, brightness), valueSelector: (p) => toTemp(p.windChillF)),
          ChartSeries(
              color: adaptiveChartColor(kColorTemperature, brightness),
              valueSelector: (p) => toTemp(p.temperature.toDouble())),
        ],
        minY: minY,
        maxY: maxY,
      ),
    );
  }

  // --- Wind barbs ---
  if (visible[kRowWindGroup] == true) {
    final speeds = periods.map((p) => toWind(p.windSpeedMph));
    final windLo = (speeds.reduce(min) - 2).clamp(0.0, double.infinity);
    final windHi = speeds.reduce(max) + 2;
    final windMin = windLo.floorToDouble();
    final windMax = windHi.ceilToDouble();
    final windInterval = _hInterval(windMin, windMax) * 2;
    map[kRowWindGroup] = ChartRowEntry(
      name: kRowWindGroup,
      height: rowHeight,
      minY: windMin,
      maxY: windMax,
      hInterval: windInterval,
      unit: useMetric ? ' km/h' : ' mph',
      legendItems: [
        (color: adaptiveChartColor(kColorWind, brightness), label: 'Wind Speed'),
      ],
      widget: WindBarbRow(
        periods: periods,
        height: rowHeight,
        minY: windMin,
        maxY: windMax,
        hInterval: windInterval,
        useMetric: useMetric,
      ),
    );
  }

  // --- Relative humidity / Precip chance / Sky cover ---
  if (visible[kRowAtmosGroup] == true) {
    const minY = 0.0;
    const maxY = 100.0;
    map[kRowAtmosGroup] = ChartRowEntry(
      name: kRowAtmosGroup,
      height: rowHeight,
      minY: minY,
      maxY: maxY,
      hInterval: _hInterval(minY, maxY),
      unit: '%',
      hideEndLabels: true,
      legendItems: [
        (color: adaptiveChartColor(kColorHumidity, brightness), label: 'Humidity'),
        (color: adaptiveChartColor(kColorPrecip, brightness), label: 'Precip'),
        (color: adaptiveChartColor(kColorSkycover, brightness), label: 'Sky Cover'),
      ],
      widget: Stack(
        children: [
          MultiLineChartRow(
            periods: periods,
            height: rowHeight,
            series: [
              ChartSeries(
                  color: adaptiveChartColor(kColorSkycover, brightness),
                  valueSelector: (p) => p.skyCoverPct.toDouble()),
              ChartSeries(
                  color: adaptiveChartColor(kColorPrecip, brightness),
                  valueSelector: (p) => p.precipChance.toDouble()),
            ],
            minY: minY,
            maxY: maxY,
          ),
          MonotoneCubicChartRow(
            periods: periods,
            height: rowHeight,
            series: [
              ChartSeries(
                  color: adaptiveChartColor(kColorHumidity, brightness),
                  valueSelector: (p) => p.relativeHumidity.toDouble()),
            ],
            minY: minY,
            maxY: maxY,
            showGrid: false,
          ),
        ],
      ),
    );
  }

  // --- Conditions (no legend, fixed 50dp height) ---
  if (visible[kRowConditions] == true) {
    map[kRowConditions] = ChartRowEntry(
      name: kRowConditions,
      height: 50.0,
      widget: ConditionsRow(periods: periods, height: 50.0),
    );
  }

  // --- Precip Detail ---
  if (visible[kRowPrecipDetail] == true) {
    const rainTypes    = {'rain', 'rain_showers'};
    const snowTypes    = {'snow', 'snow_showers'};

    final presentLineTypes = <String, Color>{};
    for (final p in periods) {
      final wt = p.weatherTypes;
      if (wt == null) continue;
      for (final type in wt.keys) {
        if (!rainTypes.contains(type) && !snowTypes.contains(type) &&
            kPrecipLineTypeColors.containsKey(type)) {
          presentLineTypes[type] = kPrecipLineTypeColors[type]!;
        }
      }
    }

    final precipLegend = <({Color color, String label})>[
      (color: kColorPrecip,         label: 'Rain'),
      (color: kColorWeatherSnow,    label: 'Snow'),
      (color: kColorWeatherThunder, label: 'Thunder'),
      for (final e in presentLineTypes.entries)
        (color: e.value, label: precipTypeLabel(e.key)),
    ];

    map[kRowPrecipDetail] = ChartRowEntry(
      name: kRowPrecipDetail,
      height: rowHeight,
      minY: 0,
      maxY: 100,
      hInterval: 25,
      unit: '%',
      hideEndLabels: true,
      legendItems: precipLegend,
      widget: PrecipDetailRow(periods: periods, height: rowHeight),
    );
  }

  // --- Solar ---
  if (visible[kRowSolar] == true) {
    map[kRowSolar] = ChartRowEntry(
      name: kRowSolar,
      height: astroHeight,
      widget: AstroRow(
        periods: periods,
        astroDays: astroDays,
        height: astroHeight,
        showSolar: true,
        showLunar: false,
      ),
    );
  }

  // --- Lunar ---
  if (visible[kRowLunar] == true) {
    map[kRowLunar] = ChartRowEntry(
      name: kRowLunar,
      height: astroHeight,
      widget: AstroRow(
        periods: periods,
        astroDays: astroDays,
        height: astroHeight,
        showSolar: false,
        showLunar: true,
      ),
    );
  }

  return rowOrder.map((r) => map[r]).whereType<ChartRowEntry>().toList();
}
