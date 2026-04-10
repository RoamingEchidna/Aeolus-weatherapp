import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/astro_day.dart';
import '../models/hourly_period.dart';
import '../providers/forecast_provider.dart';
import 'time_axis.dart';
import 'chart_scale.dart';
import 'chart_rows/multi_line_chart_row.dart';
import 'chart_rows/monotone_cubic_chart_row.dart';
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
  Timer? _autoScrollTimer;
  double _autoScrollVelocity = 0; // px per tick, negative = left
  double _xScale = 1.0; // pinch-zoom scale; 1.0 = default kPixelsPerHour
  final Set<int> _activePointers = {};
  double _baseScale = 1.0;
  DateTime? _lastTwoFingerTapTime;
  DateTime? _twoFingerDownTime;

  bool get _isPinching => _activePointers.length >= 2;

  static const Duration _kDoubleTapWindow = Duration(milliseconds: 350);
  static const Duration _kTapMaxDuration  = Duration(milliseconds: 200);

  static const double _kEdgeZone = 60.0;
  static const double _kMaxScrollSpeed = 10.0;
  static const Duration _kScrollTick = Duration(milliseconds: 16);
  static const double _kMinScale = 0.25; // 4× zoom out
  static const double _kMaxScale = 3.0;  // 3× zoom in

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
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _updateAutoScroll(double screenX, double screenWidth, double chartContentWidth) {
    final distFromLeft = screenX;
    final distFromRight = screenWidth - screenX;

    if (distFromLeft < _kEdgeZone) {
      _autoScrollVelocity = -_kMaxScrollSpeed * (1 - distFromLeft / _kEdgeZone);
    } else if (distFromRight < _kEdgeZone) {
      _autoScrollVelocity = _kMaxScrollSpeed * (1 - distFromRight / _kEdgeZone);
    } else {
      _autoScrollVelocity = 0;
    }

    if (_autoScrollVelocity != 0 && _autoScrollTimer == null) {
      _autoScrollTimer = Timer.periodic(_kScrollTick, (_) {
        if (!_scrollController.hasClients) return;
        final newOffset = (_scrollController.offset + _autoScrollVelocity)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(newOffset);
        setState(() {
          _cursorX = (_cursorX + _autoScrollVelocity)
              .clamp(0.0, chartContentWidth);
        });
      });
    } else if (_autoScrollVelocity == 0) {
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollVelocity = 0;
  }

  double get _pph => kPixelsPerHour * _xScale;

  double _initCursorX() {
    final now = DateTime.now();
    final elapsed =
        now.difference(widget.periods[0].startTime).inMinutes / 60.0;
    return (elapsed * _pph).clamp(0.0, widget.periods.length * _pph);
  }

  int get _cursorIndex =>
      (_cursorX / _pph).round().clamp(0, widget.periods.length - 1);

  DateTime get _cursorTime {
    final windowStart = widget.periods[0].startTime.toLocal();
    final minutes = (_cursorX / _pph * 60).round();
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

    final astroDays = provider.currentLocation?.cachedAstroData ?? [];

    // Use LayoutBuilder so rowHeight is derived from actual available space,
    // not the full screen height.  This prevents overflow when banners appear.
    return LayoutBuilder(builder: (context, constraints) {
      // Only scaled rows (temp/wind/atmos) flex; fixed rows (conditions, astro)
      // stay at 50dp regardless.
      final hasTemp  = visible[kRowTempGroup]  == true;
      final hasWind  = visible[kRowWindGroup]  == true;
      final hasAtmos = visible[kRowAtmosGroup] == true;
      final hasCond  = visible[kRowConditions] == true;
      final hasSolar = visible[kRowSolar]      == true;
      final hasLunar = visible[kRowLunar]      == true;
      final scaledRowCount = [hasTemp, hasWind, hasAtmos].where((v) => v).length;
      // Estimate astroHeight using a provisional rowHeight so we can compute fixedHeight.
      // We iterate once: provisional rowHeight assumes astroHeight = 0, then recompute.
      double provisionalRowHeight = scaledRowCount == 0
          ? 80.0
          : ((constraints.maxHeight - _kValuePanelHeight - kTimeAxisHeight -
                  (hasCond ? 50.0 : 0.0)) /
              scaledRowCount)
              .floorToDouble()
              .clamp(40.0, 200.0);
      final astroHeight = (provisionalRowHeight * 0.15).clamp(20.0, 50.0);
      final fixedHeight = (hasCond  ? 50.0 : 0.0) +
                          (hasSolar ? astroHeight : 0.0) +
                          (hasLunar ? astroHeight : 0.0);
      final rowHeight = scaledRowCount == 0
          ? 80.0
          : ((constraints.maxHeight - _kValuePanelHeight - kTimeAxisHeight -
                  fixedHeight) /
              scaledRowCount)
              .floorToDouble()
              .clamp(40.0, 200.0);

      final brightness = Theme.of(context).brightness;
      final rows = _buildRows(periods, visible, rowHeight, astroHeight, astroDays, brightness);
      if (rows.isEmpty) {
        return const Center(
            child: Text('All rows hidden. Enable some in the menu.'));
      }

    final pph = kPixelsPerHour * _xScale;
    final chartContentWidth = periods.length * pph;

    // --- Non-scrolling legend overlay — top-right corner of each graph row ---
    double legendTop = 0;
    final legendPositioned = <Widget>[];
    for (final entry in rows) {
      if (entry.legendItems.isNotEmpty) {
        final top = legendTop;
        legendPositioned.add(Positioned(
          top: top + 4,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: surfaceColor.withAlpha(180),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: entry.legendItems
                  .map((item) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 10, height: 10, color: item.color),
                          const SizedBox(width: 4),
                          Text(item.label, style: textTheme.labelSmall),
                        ],
                      ))
                  .toList(),
            ),
          ),
        ));
      }
      legendTop += entry.height;
    }
    final legendOverlay = IgnorePointer(
      child: Stack(children: legendPositioned),
    );

    // --- Non-scrolling y-axis label overlay (left-pinned) ---
    final yAxisOverlay = IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.map((entry) {
          if (entry.minY == null) {
            return SizedBox(height: entry.height);
          }
          const legendOffset = 0.0;
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
            height: entry.height,
            width: kLabelColumnWidth,
            child: Stack(clipBehavior: Clip.hardEdge, children: labelWidgets),
          );
        }).toList(),
      ),
    );

    final chart = Stack(
      children: [
        // Full-width horizontally scrollable chart with cursor bar inside.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _kValuePanelHeight,
          child: Listener(
            onPointerDown: (e) {
              setState(() => _activePointers.add(e.pointer));
              if (_activePointers.length == 2) {
                _twoFingerDownTime = DateTime.now();
              }
            },
            onPointerUp: (e) {
              if (_activePointers.length == 2 && _twoFingerDownTime != null) {
                final pressDuration = DateTime.now().difference(_twoFingerDownTime!);
                if (pressDuration < _kTapMaxDuration) {
                  // Quick two-finger lift — check if this is the second tap
                  final now = DateTime.now();
                  if (_lastTwoFingerTapTime != null &&
                      now.difference(_lastTwoFingerTapTime!) < _kDoubleTapWindow) {
                    setState(() => _xScale = 1.0);
                    _lastTwoFingerTapTime = null;
                  } else {
                    _lastTwoFingerTapTime = now;
                  }
                }
                _twoFingerDownTime = null;
              }
              setState(() => _activePointers.remove(e.pointer));
            },
            onPointerCancel: (e) {
              _twoFingerDownTime = null;
              setState(() => _activePointers.remove(e.pointer));
            },
            child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: _isPinching
                ? const NeverScrollableScrollPhysics()
                : const ScrollPhysics(),
            padding: EdgeInsets.only(
              left: kLabelColumnWidth + pph,
              right: pph + kLabelColumnWidth,
            ),
            child: GestureDetector(
              onDoubleTap: () => setState(() => _cursorX = _initCursorX()),
              onLongPressStart: (details) {
                if (_isPinching) return;
                setState(() {
                  _cursorX = details.localPosition.dx.clamp(0.0, chartContentWidth.toDouble());
                  _cursorDragging = true;
                });
              },
              onLongPressMoveUpdate: (details) {
                if (_isPinching) return;
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
                  OverflowBox(
                    alignment: Alignment.topLeft,
                    maxHeight: double.infinity,
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TimeAxis(periods: periods),
                      ...rows.expand((entry) => [
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
                  )),
                  // Cursor bar — spans full height including time axis.
                  Positioned(
                    left: _cursorX - _kCursorHitWidth / 2,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragDown: (_) {
                        if (_isPinching) return;
                        setState(() => _cursorDragging = true);
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_isPinching) return;
                        final screenWidth = MediaQuery.of(context).size.width;
                        setState(() {
                          _cursorX = (_cursorX + details.delta.dx)
                              .clamp(0.0, chartContentWidth);
                        });
                        _updateAutoScroll(details.globalPosition.dx, screenWidth, chartContentWidth);
                      },
                      onHorizontalDragEnd: (_) {
                        _stopAutoScroll();
                        setState(() => _cursorDragging = false);
                      },
                      onHorizontalDragCancel: () {
                        _stopAutoScroll();
                        setState(() => _cursorDragging = false);
                      },
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
          child: _buildValuePanel(context, periods[_cursorIndex], visible, _cursorTime, astroDays),
        ),
      ],
    );

    return ChartScale(
      pixelsPerHour: pph,
      child: GestureDetector(
        onScaleStart: (details) {
          if (!_isPinching) return;
          _baseScale = _xScale;
        },
        onScaleUpdate: (details) {
          if (!_isPinching) return;
          const sensitivity = 1.0;
          final rawScale = _baseScale * details.scale;
          final next = (_baseScale + (rawScale - _baseScale) * sensitivity)
              .clamp(_kMinScale, _kMaxScale);
          if ((next - _xScale).abs() > 0.005) {
            // Keep the focal point anchored: compute chart-x at the pinch
            // center, then after scaling scroll so that point stays put.
            if (_scrollController.hasClients) {
              final focalX = details.localFocalPoint.dx;
              final chartX = _scrollController.offset + focalX;
              final newOffset = chartX * (next / _xScale) - focalX;
              setState(() => _xScale = next);
              _scrollController.jumpTo(
                newOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
              );
            } else {
              setState(() => _xScale = next);
            }
          }
        },
        child: chart,
      ),
    );
    }); // end LayoutBuilder
  }

  Widget _buildValuePanel(
      BuildContext context, HourlyPeriod p, Map<String, bool> visible, DateTime cursorTime, List<AstroDay> astroDays) {
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
    line1.add(cell(timeFmt.format(cursorTime), scheme.onSurface, 82));
    if (uvIndex != null) {
      line1.add(sep());
      line1.add(cell('UV $uvIndex', kColorAstroNoon, 44));
    }
    if (visible[kRowTempGroup] == true) {
      line1.add(sep());
      line1.add(cell('${p.temperature}°', adaptiveChartColor(kColorTemperature, brightness), 36));
      line1.add(sep());
      line1.add(cell('WC ${p.windChillF.round()}°', adaptiveChartColor(kColorWindChill, brightness), 54));
      line1.add(sep());
      line1.add(cell('Dew ${p.dewpointF.round()}°', adaptiveChartColor(kColorDewpoint, brightness), 58));
    }

    // Line 2: wind + atmos group.
    final line2 = <Widget>[];
    if (visible[kRowWindGroup] == true) {
      line2.add(cell('${p.windSpeedMph.round()} mph ${p.windDirection}', adaptiveChartColor(kColorWind, brightness), 80));
    }
    if (visible[kRowAtmosGroup] == true) {
      if (line2.isNotEmpty) line2.add(sep());
      line2.add(cell('RH ${p.relativeHumidity}%', adaptiveChartColor(kColorHumidity, brightness), 62));
      line2.add(sep());
      line2.add(cell('Precip ${p.precipChance}%', adaptiveChartColor(kColorPrecip, brightness), 74));
      line2.add(sep());
      line2.add(cell('Sky ${p.skyCoverPct}%', adaptiveChartColor(kColorSkycover, brightness), 70));
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
        ],
      ),
    );
  }

  List<_RowEntry> _buildRows(
      List<HourlyPeriod> periods, Map<String, bool> visible, double rowHeight, double astroHeight, List<AstroDay> astroDays, Brightness brightness) {
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
                color: adaptiveChartColor(kColorDewpoint, brightness), valueSelector: (p) => p.dewpointF),
            ChartSeries(
                color: adaptiveChartColor(kColorWindChill, brightness), valueSelector: (p) => p.windChillF),
            ChartSeries(
                color: adaptiveChartColor(kColorTemperature, brightness),
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
      final windInterval = _hInterval(windMin, windMax) * 2;
      entries.add(_RowEntry(
        name: kRowWindGroup,
        height: rowHeight,
        minY: windMin,
        maxY: windMax,
        hInterval: windInterval,
        unit: ' mph',
        legendItems: [
          (color: adaptiveChartColor(kColorWind, brightness), label: 'Wind Speed'),
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

    // --- Solar ---
    if (visible[kRowSolar] == true) {
      entries.add(_RowEntry(
        name: kRowSolar,
        height: astroHeight,
        widget: AstroRow(
          periods: periods,
          astroDays: astroDays,
          height: astroHeight,
          showSolar: true,
          showLunar: false,
        ),
      ));
    }

    // --- Lunar ---
    if (visible[kRowLunar] == true) {
      entries.add(_RowEntry(
        name: kRowLunar,
        height: astroHeight,
        widget: AstroRow(
          periods: periods,
          astroDays: astroDays,
          height: astroHeight,
          showSolar: false,
          showLunar: true,
        ),
      ));
    }

    return entries;
  }
}
