import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/hourly_period.dart';
import '../providers/forecast_provider.dart';
import 'time_axis.dart';
import 'chart_rows/line_chart_row.dart';
import 'chart_rows/bar_chart_row.dart';
import 'chart_rows/area_chart_row.dart';
import 'chart_rows/wind_direction_row.dart';
import 'chart_rows/conditions_row.dart';

class ScrollableChart extends StatelessWidget {
  final List<HourlyPeriod> periods;

  const ScrollableChart({super.key, required this.periods});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ForecastProvider>();
    final visible = provider.visibleRows;
    final textTheme = Theme.of(context).textTheme;

    final rows = _buildRows(periods, visible);
    if (rows.isEmpty) {
      return const Center(
          child: Text('All rows hidden. Enable some in the menu.'));
    }

    final labels = _visibleLabels(visible);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pinned label column
        SizedBox(
          width: kLabelColumnWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(height: kTimeAxisHeight),
              ...labels.map((label) => SizedBox(
                    height: kChartRowHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        child: Text(label,
                            style: textTheme.labelSmall,
                            textAlign: TextAlign.right),
                      ),
                    ),
                  )),
            ],
          ),
        ),
        // Scrollable chart area
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TimeAxis(periods: periods),
                ...rows,
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<String> _visibleLabels(Map<String, bool> visible) =>
      kAllRows.where((r) => visible[r] == true).toList();

  List<Widget> _buildRows(
      List<HourlyPeriod> periods, Map<String, bool> visible) {
    final widgets = <Widget>[];

    void addIf(String key, Widget widget) {
      if (visible[key] == true) widgets.add(widget);
    }

    addIf(
        kRowTemperature,
        LineChartRow(
          periods: periods,
          color: kColorTemperature,
          valueSelector: (p) => p.temperature.toDouble(),
        ));
    addIf(
        kRowDewpoint,
        LineChartRow(
          periods: periods,
          color: kColorDewpoint,
          valueSelector: (p) => p.dewpointF,
        ));
    addIf(
        kRowPrecip,
        BarChartRow(
          periods: periods,
          color: kColorPrecip,
          valueSelector: (p) => p.precipChance.toDouble(),
          maxY: 100,
        ));
    addIf(
        kRowHumidity,
        AreaChartRow(
          periods: periods,
          color: kColorHumidity,
          valueSelector: (p) => p.relativeHumidity.toDouble(),
        ));

    final maxWind = periods.isEmpty
        ? 50.0
        : periods
                .map((p) => p.windSpeedMph)
                .reduce((a, b) => a > b ? a : b) +
            5;
    addIf(
        kRowWindSpeed,
        BarChartRow(
          periods: periods,
          color: kColorWindSpeed,
          valueSelector: (p) => p.windSpeedMph,
          maxY: maxWind,
        ));
    addIf(kRowWindDirection, WindDirectionRow(periods: periods));
    addIf(kRowConditions, ConditionsRow(periods: periods));

    return widgets;
  }
}
