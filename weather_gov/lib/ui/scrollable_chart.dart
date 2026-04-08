import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/astro_day.dart';
import '../models/hourly_period.dart';
import '../providers/forecast_provider.dart';
import 'time_axis.dart';
import 'chart_rows/multi_line_chart_row.dart';
import 'chart_rows/wind_barb_row.dart';
import 'chart_rows/conditions_row.dart';
import 'chart_rows/astro_row.dart';

const double _kLegendBarHeight = 20.0;
const double _kValuePanelHeight = 64.0;
// Width of the invisible drag hit area centered on the 2px cursor bar.
const double _kCursorHitWidth = 24.0;

// Carries a chart row widget plus optional y-axis scale and legend info.
class _RowEntry {
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

class ScrollableChart extends StatefulWidget {
  final List<HourlyPeriod> periods;

  const ScrollableChart({super.key, required this.periods});

  @override
  State<ScrollableChart> createState() => _ScrollableChartState();
}

class _ScrollableChartState extends State<ScrollableChart> {
  late double _cursorX;
  bool _cursorDragging = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _cursorX = _initCursorX();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(kLabelColumnWidth);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _initCursorX() {
    final now = DateTime.now();
    final elapsed =
        now.difference(widget.periods[0].startTime).inMinutes / 60.0;
    return (elapsed * kPixelsPerHour)
        .clamp(0.0, widget.periods.length * kPixelsPerHour);
  }

  int get _cursorIndex =>
      (_cursorX / kPixelsPerHour).round().clamp(0, widget.periods.length - 1);

  DateTime get _cursorTime {
    final windowStart = widget.periods[0].startTime.toLocal();
    final minutes = (_cursorX / kPixelsPerHour * 60).round();
    return windowStart.add(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final periods = widget.periods;
    final provider = context.watch<ForecastProvider>();
    final visible = provider.visibleRows;
    final textTheme = Theme.of(context).textTheme;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final rowBorderColor = Theme.of(context).colorScheme.outline;
    final rowHeight = (MediaQuery.of(context).size.height * 0.20).floorToDouble();

    final astroDays = provider.currentLocation?.cachedAstroData ?? [];
    final rows = _buildRows(periods, visible, rowHeight, astroDays);
    if (rows.isEmpty) {
      return const Center(
          child: Text('All rows hidden. Enable some in the menu.'));
    }

    final chartContentWidth = periods.length * kPixelsPerHour;

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
        // Full-width horizontally scrollable chart with cursor bar inside.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _kValuePanelHeight,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(
              left: kLabelColumnWidth + kPixelsPerHour,
              right: kPixelsPerHour + kLabelColumnWidth,
            ),
            child: GestureDetector(
              onDoubleTap: () => setState(() => _cursorX = _initCursorX()),
              onLongPressStart: (details) {
                setState(() {
                  _cursorX = details.localPosition.dx.clamp(0.0, chartContentWidth.toDouble());
                  _cursorDragging = true;
                });
              },
              onLongPressMoveUpdate: (details) {
                setState(() {
                  _cursorX = details.localPosition.dx.clamp(0.0, chartContentWidth.toDouble());
                });
              },
              onLongPressEnd: (_) => setState(() => _cursorDragging = false),
              onLongPressCancel: () => setState(() => _cursorDragging = false),
              child: SizedBox(
              width: chartContentWidth,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Chart content column.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TimeAxis(periods: periods),
                      ...rows.expand((entry) => [
                            if (entry.legendItems.isNotEmpty)
                              SizedBox(height: entry.legendBarHeight),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                      color: rowBorderColor, width: 1.0),
                                  bottom: BorderSide(
                                      color: rowBorderColor, width: 1.0),
                                ),
                              ),
                              child: entry.widget,
                            ),
                          ]),
                    ],
                  ),
                  // Cursor bar — spans full height including time axis.
                  Positioned(
                    left: _cursorX - _kCursorHitWidth / 2,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragDown: (_) =>
                          setState(() => _cursorDragging = true),
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _cursorX = (_cursorX + details.delta.dx)
                              .clamp(0.0, chartContentWidth);
                        });
                      },
                      onHorizontalDragEnd: (_) =>
                          setState(() => _cursorDragging = false),
                      onHorizontalDragCancel: () =>
                          setState(() => _cursorDragging = false),
                      child: SizedBox(
                        width: _kCursorHitWidth,
                        child: Center(
                          child: Container(
                            width: _cursorDragging ? 3.5 : 2.0,
                            color: kColorCursor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
        // Legend overlay — pinned below the time axis, full width.
        Positioned(
          left: 0,
          right: 0,
          top: kTimeAxisHeight,
          bottom: _kValuePanelHeight,
          child: legendOverlay,
        ),
        // Y-axis label overlay — pinned to the left, below the time axis.
        Positioned(
          left: 0,
          top: kTimeAxisHeight,
          width: kLabelColumnWidth,
          bottom: _kValuePanelHeight,
          child: yAxisOverlay,
        ),
        // Value panel — fixed at the bottom, shows cursor period values.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _kValuePanelHeight,
          child: _buildValuePanel(context, periods[_cursorIndex], visible, _cursorTime),
        ),
      ],
    );
  }

  Widget _buildValuePanel(
      BuildContext context, HourlyPeriod p, Map<String, bool> visible, DateTime cursorTime) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final screenWidth = MediaQuery.of(context).size.width;
    final timeFmt = DateFormat('EEE HH:mm');

    final valueStyle = textTheme.labelMedium!.copyWith(fontSize: 16);

    // Fixed-width cell so values never shift neighbours when digits change.
    Widget cell(String text, Color color, double width) => SizedBox(
          width: width,
          child: Text(
            text,
            style: valueStyle.copyWith(color: color),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        );

    // Narrow separator — just 4px of breathing room between cells.
    Widget sep() => SizedBox(
          width: 20,
          child: Text('·',
              textAlign: TextAlign.center,
              style: valueStyle.copyWith(color: scheme.onSurfaceVariant)),
        );

    // Line 1: time + temperature group.
    final line1 = <Widget>[];
    line1.add(cell(timeFmt.format(cursorTime), scheme.onSurface, 82));
    if (visible[kRowTempGroup] == true) {
      line1.add(sep());
      line1.add(cell('${p.temperature}°', kColorTemperature, 36));
      line1.add(sep());
      line1.add(cell('WC ${p.windChillF.round()}°', kColorWindChill, 54));
      line1.add(sep());
      line1.add(cell('Dew ${p.dewpointF.round()}°', kColorDewpoint, 58));
    }

    // Line 2: wind + atmos group.
    final line2 = <Widget>[];
    if (visible[kRowWindGroup] == true) {
      line2.add(cell('${p.windSpeedMph.round()} mph ${p.windDirection}', kColorWind, 80));
    }
    if (visible[kRowAtmosGroup] == true) {
      if (line2.isNotEmpty) line2.add(sep());
      line2.add(cell('RH ${p.relativeHumidity}%', kColorHumidity, 62));
      line2.add(sep());
      line2.add(cell('Precip ${p.precipChance}%', kColorPrecip, 74));
      line2.add(sep());
      line2.add(cell('Sky ${p.skyCoverPct}%', kColorSkycover, 70));
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
        color: brightness == Brightness.light ? kLightPanelBackground : kDarkPanelBackground,
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
        ],
      ),
    );
  }

  List<_RowEntry> _buildRows(
      List<HourlyPeriod> periods, Map<String, bool> visible, double rowHeight, List<AstroDay> astroDays) {
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
      final speeds = periods.map((p) => p.windSpeedMph);
      final windLo = (speeds.reduce(min) - 2).clamp(0.0, double.infinity);
      final windHi = speeds.reduce(max) + 2;
      final windMin = windLo.floorToDouble();
      final windMax = windHi.ceilToDouble();
      final windInterval = _hInterval(windMin, windMax);
      entries.add(_RowEntry(
        name: kRowWindGroup,
        height: rowHeight,
        minY: windMin,
        maxY: windMax,
        hInterval: windInterval,
        unit: ' mph',
        legendItems: const [
          (color: kColorWind, label: 'Wind Speed'),
        ],
        widget: WindBarbRow(
          periods: periods,
          height: rowHeight,
          minY: windMin,
          maxY: windMax,
          hInterval: windInterval,
        ),
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

    // --- Astronomical (no legend, fixed 50dp height) ---
    if (visible[kRowAstro] == true) {
      entries.add(_RowEntry(
        name: kRowAstro,
        height: 50.0,
        widget: AstroRow(periods: periods, astroDays: astroDays),
      ));
    }

    return entries;
  }
}
