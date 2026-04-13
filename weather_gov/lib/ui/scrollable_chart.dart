import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
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
import 'chart_rows/precip_detail_row.dart';
import 'chart_rows/astro_row.dart';

const Map<String, Color> _kPrecipLineTypeColors = {
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
  final bool hideEndLabels;

  const _RowEntry({
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

class _ScrollableChartState extends State<ScrollableChart>
    with WidgetsBindingObserver {
  late double _cursorX;
  bool _cursorDragging = false;
  final _scrollController = ScrollController();
  final _vertScrollController = ScrollController();
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
    WidgetsBinding.instance.addObserver(this);
    _cursorX = _initCursorX();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(kLabelColumnWidth);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _vertScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Stop any in-progress auto-scroll and clear active pointer tracking
    // so orientation changes don't trigger setState mid-frame.
    _stopAutoScroll();
    if (_activePointers.isNotEmpty) {
      setState(() {
        _activePointers.clear();
        _cursorDragging = false;
      });
    }
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
    final tzOffset = context.read<ForecastProvider>().currentLocation?.tzOffsetHours ?? 0;
    final windowStart = widget.periods[0].startTime.toUtc().add(Duration(hours: tzOffset));
    final minutes = (_cursorX / _pph * 60).round();
    return windowStart.add(Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final periods = widget.periods;
    final provider = context.watch<ForecastProvider>();
    final visible = provider.visibleRows;
    final useMetric = provider.useMetric;
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
      final hasCond        = visible[kRowConditions]   == true;
      final hasPrecipDetail = visible[kRowPrecipDetail] == true;
      final valuePanelHeight = hasPrecipDetail ? 88.0 : _kValuePanelHeight;
      final hasSolar       = visible[kRowSolar]         == true;
      final hasLunar       = visible[kRowLunar]         == true;
      final scaledRowCount = [hasTemp, hasWind, hasAtmos, hasPrecipDetail].where((v) => v).length;
      // Estimate astroHeight using a provisional rowHeight so we can compute fixedHeight.
      double provisionalRowHeight = scaledRowCount == 0
          ? 80.0
          : ((constraints.maxHeight - valuePanelHeight - kTimeAxisHeight -
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
          : ((constraints.maxHeight - valuePanelHeight - kTimeAxisHeight -
                  fixedHeight) /
              scaledRowCount)
              .floorToDouble()
              .clamp(kMinChartRowHeight, 200.0);

      final brightness = Theme.of(context).brightness;
      final rows = _buildRows(periods, visible, provider.rowOrder, rowHeight, astroHeight, astroDays, brightness, useMetric);
      if (rows.isEmpty) {
        return const Center(
            child: Text('All rows hidden. Enable some in the menu.'));
      }

    final pph = kPixelsPerHour * _xScale;
    final chartContentWidth = periods.length * pph;
    final totalChartHeight = kTimeAxisHeight + rows.fold(0.0, (s, r) => s + r.height);

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
            if (entry.hideEndLabels &&
                (v <= entry.minY! + 0.001 || v >= entry.maxY! - 0.001)) {
              continue;
            }
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

    // Scrollable chart body (vertical + horizontal).
    // Overlays (y-axis, legend) live inside the vertical scroll so they move with rows.
    final chartBody = SingleChildScrollView(
      controller: _vertScrollController,
      scrollDirection: Axis.vertical,
      physics: _isPinching
          ? const NeverScrollableScrollPhysics()
          : const ScrollPhysics(),
      child: SizedBox(
        height: totalChartHeight,
        child: Stack(
          children: [
            // Horizontal chart scroll + cursor.
            Positioned.fill(
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
                          OverflowBox(
                            alignment: Alignment.topLeft,
                            maxHeight: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TimeAxis(periods: periods, use24Hour: provider.use24Hour),
                                ...rows.expand((entry) => [
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
                          // Cursor bar.
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
                                  _cursorX = (_cursorX + details.delta.dx).clamp(0.0, chartContentWidth);
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
            // Legend overlay — scrolls vertically with content.
            Positioned(
              left: 0,
              right: 0,
              top: kTimeAxisHeight,
              bottom: 0,
              child: legendOverlay,
            ),
            // Y-axis label overlay — scrolls vertically with content.
            Positioned(
              left: 0,
              top: kTimeAxisHeight,
              width: kLabelColumnWidth,
              bottom: 0,
              child: yAxisOverlay,
            ),
          ],
        ),
      ),
    );

    final chart = Column(
      children: [
        Expanded(child: chartBody),
        SizedBox(
          height: valuePanelHeight,
          child: _buildValuePanel(context, periods[_cursorIndex], visible, _cursorTime, astroDays,
              use24Hour: provider.use24Hour, useMetric: useMetric),
        ),
      ],
    );

    return ChartScale(
      pixelsPerHour: pph,
      tzOffsetHours: provider.currentLocation?.tzOffsetHours ?? 0,
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
            final ratio = next / _xScale;
            if (_scrollController.hasClients) {
              final focalX = details.localFocalPoint.dx;
              final chartX = _scrollController.offset + focalX;
              final newOffset = chartX * ratio - focalX;
              setState(() {
                _cursorX *= ratio;
                _xScale = next;
              });
              _scrollController.jumpTo(
                newOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
              );
            } else {
              setState(() {
                _cursorX *= ratio;
                _xScale = next;
              });
            }
          }
        },
        child: chart,
      ),
    );
    }); // end LayoutBuilder
  }

  Widget _buildValuePanel(
      BuildContext context, HourlyPeriod p, Map<String, bool> visible, DateTime cursorTime, List<AstroDay> astroDays, {required bool use24Hour, required bool useMetric}) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final screenWidth = MediaQuery.of(context).size.width;
    final timeFmt = DateFormat(use24Hour ? 'EEE HH:mm' : 'EEE h:mm a');

    final valueStyle = textTheme.labelMedium!.copyWith(fontSize: 16);

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
        final label = e.key.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
        line3.add(sep());
        final typeColor = _kPrecipLineTypeColors[e.key] ?? scheme.onSurfaceVariant;
        line3.add(cell(adaptiveShort(label, '${e.value}%', cw3), typeColor, cw3));
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

  List<_RowEntry> _buildRows(
      List<HourlyPeriod> periods, Map<String, bool> visible, List<String> rowOrder, double rowHeight, double astroHeight, List<AstroDay> astroDays, Brightness brightness, bool useMetric) {
    final map = <String, _RowEntry>{};

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
      map[kRowTempGroup] = _RowEntry(
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
      map[kRowWindGroup] = _RowEntry(
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
      map[kRowAtmosGroup] = _RowEntry(
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
      map[kRowConditions] = _RowEntry(
        name: kRowConditions,
        height: 50.0,
        widget: ConditionsRow(periods: periods, height: 50.0),
      );
    }

    // --- Precip Detail ---
    if (visible[kRowPrecipDetail] == true) {
      const rainTypes    = {'rain', 'rain_showers'};
      const snowTypes    = {'snow', 'snow_showers'};
      const lineTypeColors = _kPrecipLineTypeColors;

      final presentLineTypes = <String, Color>{};
      for (final p in periods) {
        final wt = p.weatherTypes;
        if (wt == null) continue;
        for (final type in wt.keys) {
          if (!rainTypes.contains(type) && !snowTypes.contains(type) &&
              lineTypeColors.containsKey(type)) {
            presentLineTypes[type] = lineTypeColors[type]!;
          }
        }
      }

      final precipLegend = <({Color color, String label})>[
        (color: kColorPrecip,         label: 'Rain'),
        (color: kColorWeatherSnow,    label: 'Snow'),
        (color: kColorWeatherThunder, label: 'Thunder'),
        for (final e in presentLineTypes.entries)
          (color: e.value, label: e.key.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')),
      ];

      map[kRowPrecipDetail] = _RowEntry(
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
      map[kRowSolar] = _RowEntry(
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
      map[kRowLunar] = _RowEntry(
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

    return rowOrder.map((r) => map[r]).whereType<_RowEntry>().toList();
  }
}
