import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/hourly_period.dart';
import '../providers/forecast_provider.dart';
import '../providers/settings_provider.dart';
import 'time_axis.dart';
import 'chart_scale.dart';
import 'chart_row_entries.dart';
import 'chart_overlays.dart';
import 'chart_value_panel.dart';

// Width of the invisible drag hit area centered on the 2px cursor bar.
const double _kCursorHitWidth = 24.0;

/// The scrollable, zoomable forecast chart: row layout comes from
/// chart_row_entries.dart, overlays from chart_overlays.dart and the readout
/// from chart_value_panel.dart. This file owns cursor, scroll and pinch state.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCursor());
  }

  @override
  void didUpdateWidget(ScrollableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New forecast data (refresh, overnight sync, location switch) shifts
    // what each x-position means, so snap the cursor back to now.
    if (widget.periods.isNotEmpty &&
        (oldWidget.periods.isEmpty ||
            widget.periods.first.startTime != oldWidget.periods.first.startTime)) {
      _cursorX = _initCursorX();
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCursor());
    }
  }

  /// Scrolls so the cursor sits in the middle of the visible chart area
  /// (right of the y-axis label column).
  void _centerOnCursor({bool animate = false}) {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Cursor's x in scroll-content coordinates includes the left padding.
    final cursorContentX = kLabelColumnWidth + _pph + _cursorX;
    final visibleCenter =
        kLabelColumnWidth + (position.viewportDimension - kLabelColumnWidth) / 2;
    final target =
        (cursorContentX - visibleCenter).clamp(0.0, position.maxScrollExtent);
    if (animate) {
      _scrollController.animateTo(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      _scrollController.jumpTo(target);
    }
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
    final settings = context.watch<SettingsProvider>();
    final visible = settings.visibleRows;
    final useMetric = settings.useMetric;
    final rowBorderColor = Theme.of(context).colorScheme.outline;

    final astroDays = provider.currentLocation?.cachedAstroData ?? [];

    // Use LayoutBuilder so rowHeight is derived from actual available space,
    // not the full screen height.  This prevents overflow when banners appear.
    return LayoutBuilder(builder: (context, constraints) {
      final heights = computeRowHeights(visible, constraints.maxHeight);
      final valuePanelHeight = heights.valuePanelHeight;

      final rows = buildChartRows(
        periods: periods,
        visible: visible,
        rowOrder: settings.rowOrder,
        rowHeight: heights.rowHeight,
        astroHeight: heights.astroHeight,
        astroDays: astroDays,
        brightness: Theme.of(context).brightness,
        useMetric: useMetric,
      );
      if (rows.isEmpty) {
        return const Center(
            child: Text('All rows hidden. Enable some in the menu.'));
      }

    final pph = kPixelsPerHour * _xScale;
    final chartContentWidth = periods.length * pph;
    final totalChartHeight = kTimeAxisHeight + rows.fold(0.0, (s, r) => s + r.height);

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
                        // Cursor is in pixels, so it has to scale with the
                        // zoom or it lands on a different hour.
                        setState(() {
                          _cursorX /= _xScale;
                          _xScale = 1.0;
                        });
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _centerOnCursor());
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
                    onDoubleTap: () {
                      setState(() => _cursorX = _initCursorX());
                      _centerOnCursor(animate: true);
                    },
                    onLongPressStart: (details) {
                      if (_isPinching) return;
                      HapticFeedback.selectionClick();
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
                                TimeAxis(periods: periods, use24Hour: settings.use24Hour),
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
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    curve: Curves.easeOut,
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
              child: RowLegendOverlay(rows: rows),
            ),
            // Y-axis label overlay — scrolls vertically with content.
            Positioned(
              left: 0,
              top: kTimeAxisHeight,
              width: kLabelColumnWidth,
              bottom: 0,
              child: YAxisLabelOverlay(rows: rows),
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
          child: ChartValuePanel(
            period: periods[_cursorIndex],
            visible: visible,
            cursorTime: _cursorTime,
            astroDays: astroDays,
            use24Hour: settings.use24Hour,
            useMetric: useMetric,
          ),
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
}
