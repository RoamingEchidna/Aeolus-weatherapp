import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/hourly_period.dart';
import '../providers/forecast_provider.dart';
import 'time_axis.dart';
import 'chart_rows/multi_line_chart_row.dart';
import 'chart_rows/wind_barb_row.dart';
import 'chart_rows/conditions_row.dart';

const double _kLegendBarHeight = 20.0;

// Carries a chart row widget plus optional y-axis scale and legend info.
class _RowEntry {
  final String name;
  final Widget widget;
  final double height;
  // Null for rows without a numeric y-axis (Wind, Conditions).
  final double? minY;
  final double? maxY;
  final double? hInterval;
  final String unit;
  // Empty for rows without a color legend (Conditions).
  final List<({Color color, String label})> legendItems;

  const _RowEntry({
    required this.name,
    required this.widget,
    required this.height,
    this.minY,
    this.maxY,
    this.hInterval,
    this.unit = '',
    this.legendItems = const [],
  });

  double get legendBarHeight =>
      legendItems.isEmpty ? 0.0 : _kLegendBarHeight;

  // Total vertical space this row occupies (legend bar + chart).
  double get totalHeight => legendBarHeight + height;
}

// Matches the hInterval logic in MultiLineChartRow so labels align with grid lines.
double _hInterval(double lo, double hi) {
  final range = hi - lo;
  return range > 80 ? 20.0 : range > 40 ? 10.0 : range > 20 ? 5.0 : 2.0;
}

class ScrollableChart extends StatelessWidget {
  final List<HourlyPeriod> periods;

  const ScrollableChart({super.key, required this.periods});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ForecastProvider>();
    final visible = provider.visibleRows;
    final textTheme = Theme.of(context).textTheme;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final rowBorderColor = Theme.of(context).colorScheme.outline;
    final rowHeight = MediaQuery.of(context).size.height * 0.20;

    final rows = _buildRows(periods, visible, rowHeight);
    if (rows.isEmpty) {
      return const Center(
          child: Text('All rows hidden. Enable some in the menu.'));
    }

    // --- Non-scrolling legend overlay (full width, above each chart row) ---
    final legendOverlay = IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.map((entry) {
          if (entry.legendItems.isEmpty) {
            return SizedBox(height: entry.totalHeight);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: entry.legendBarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: entry.legendItems
                        .map((item) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                    width: 10,
                                    height: 10,
                                    color: item.color),
                                const SizedBox(width: 4),
                                Text(item.label,
                                    style: textTheme.labelSmall),
                              ],
                            ))
                        .toList(),
                  ),
                ),
              ),
              SizedBox(height: entry.height),
            ],
          );
        }).toList(),
      ),
    );

    // --- Non-scrolling y-axis label overlay (left-pinned) ---
    final yAxisOverlay = IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.map((entry) {
          if (entry.minY == null) {
            return SizedBox(height: entry.totalHeight);
          }
          final legendOffset = entry.legendBarHeight;
          final first =
              (entry.minY! / entry.hInterval!).ceil() * entry.hInterval!;
          final labelWidgets = <Widget>[];
          for (double v = first;
              v <= entry.maxY! + 0.001;
              v += entry.hInterval!) {
            final t = entry.height *
                (1.0 - (v - entry.minY!) / (entry.maxY! - entry.minY!));
            final clampedTop = (legendOffset + t - 6)
                .clamp(legendOffset, legendOffset + entry.height - 12.0);
            labelWidgets.add(Positioned(
              left: 4,
              top: clampedTop,
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor.withAlpha(180),
                  borderRadius: BorderRadius.circular(2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '${v.round()}${entry.unit}',
                  style: textTheme.labelSmall,
                ),
              ),
            ));
          }
          return SizedBox(
            height: entry.totalHeight,
            width: kLabelColumnWidth,
            child: Stack(clipBehavior: Clip.hardEdge, children: labelWidgets),
          );
        }).toList(),
      ),
    );

    return Stack(
        children: [
          // Full-width horizontally scrollable chart.
          Positioned.fill(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: kPixelsPerHour),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TimeAxis(periods: periods),
                  // Each row: spacer for legend bar + chart widget.
                  ...rows.expand((entry) => [
                        if (entry.legendItems.isNotEmpty)
                          SizedBox(height: entry.legendBarHeight),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: rowBorderColor, width: 1.0),
                              bottom: BorderSide(color: rowBorderColor, width: 1.0),
                            ),
                          ),
                          child: entry.widget,
                        ),
                      ]),
                ],
              ),
            ),
          ),
          // Legend overlay — pinned below the time axis, full width.
          Positioned(
            left: 0,
            right: 0,
            top: kTimeAxisHeight,
            bottom: 0,
            child: legendOverlay,
          ),
          // Y-axis label overlay — pinned to the left, below the time axis.
          Positioned(
            left: 0,
            top: kTimeAxisHeight,
            width: kLabelColumnWidth,
            bottom: 0,
            child: yAxisOverlay,
          ),
        ],
      );
  }

  List<_RowEntry> _buildRows(
      List<HourlyPeriod> periods, Map<String, bool> visible, double rowHeight) {
    final entries = <_RowEntry>[];

    // --- Temperature / Wind Chill / Dewpoint ---
    if (visible[kRowTempGroup] == true) {
      final allTemps = periods.expand((p) => [
            p.temperature.toDouble(),
            p.windChillF,
            p.dewpointF,
          ]);
      final lo = allTemps.reduce(min);
      final hi = allTemps.reduce(max);
      final minY = (lo - 4).floorToDouble();
      final maxY = (hi + 4).ceilToDouble();
      entries.add(_RowEntry(
        name: kRowTempGroup,
        height: rowHeight,
        minY: minY,
        maxY: maxY,
        hInterval: _hInterval(minY, maxY),
        unit: '°',
        legendItems: const [
          (color: kColorTemperature, label: 'Temp'),
          (color: kColorWindChill, label: 'Wind Chill'),
          (color: kColorDewpoint, label: 'Dewpoint'),
        ],
        widget: MultiLineChartRow(
          periods: periods,
          height: rowHeight,
          series: [
            ChartSeries(
                color: kColorDewpoint, valueSelector: (p) => p.dewpointF),
            ChartSeries(
                color: kColorWindChill, valueSelector: (p) => p.windChillF),
            ChartSeries(
                color: kColorTemperature,
                valueSelector: (p) => p.temperature.toDouble()),
          ],
          minY: minY,
          maxY: maxY,
        ),
      ));
    }

    // --- Wind barbs ---
    if (visible[kRowWindGroup] == true) {
      entries.add(_RowEntry(
        name: kRowWindGroup,
        height: rowHeight,
        legendItems: const [
          (color: kColorWind, label: 'Wind'),
        ],
        widget: WindBarbRow(periods: periods, height: rowHeight),
      ));
    }

    // --- Relative humidity / Precip chance / Sky cover ---
    if (visible[kRowAtmosGroup] == true) {
      const minY = 0.0;
      const maxY = 100.0;
      entries.add(_RowEntry(
        name: kRowAtmosGroup,
        height: rowHeight,
        minY: minY,
        maxY: maxY,
        hInterval: _hInterval(minY, maxY),
        unit: '%',
        legendItems: const [
          (color: kColorHumidity, label: 'Humidity'),
          (color: kColorPrecip, label: 'Precip'),
          (color: kColorSkycover, label: 'Sky Cover'),
        ],
        widget: MultiLineChartRow(
          periods: periods,
          height: rowHeight,
          series: [
            ChartSeries(
                color: kColorSkycover,
                valueSelector: (p) => p.skyCoverPct.toDouble()),
            ChartSeries(
                color: kColorPrecip,
                valueSelector: (p) => p.precipChance.toDouble()),
            ChartSeries(
                color: kColorHumidity,
                valueSelector: (p) => p.relativeHumidity.toDouble()),
          ],
          minY: minY,
          maxY: maxY,
        ),
      ));
    }

    // --- Conditions (no legend, fixed 50dp height) ---
    if (visible[kRowConditions] == true) {
      entries.add(_RowEntry(
        name: kRowConditions,
        height: 50.0,
        widget: ConditionsRow(periods: periods, height: 50.0),
      ));
    }

    return entries;
  }
}
