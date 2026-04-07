import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';

class ChartSeries {
  final Color color;
  final double Function(HourlyPeriod) valueSelector;
  const ChartSeries({required this.color, required this.valueSelector});
}

class MultiLineChartRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final List<ChartSeries> series;
  // If null, bounds are auto-computed from data with padding.
  final double? minY;
  final double? maxY;
  final double height;

  const MultiLineChartRow({
    super.key,
    required this.periods,
    required this.series,
    this.minY,
    this.maxY,
    this.height = kChartRowHeight,
  });

  @override
  Widget build(BuildContext context) {
    final gridColor =
        Theme.of(context).colorScheme.outline.withAlpha(70);

    // Compute bounds from all series when not provided.
    double lo = minY ?? double.infinity;
    double hi = maxY ?? double.negativeInfinity;
    if (minY == null || maxY == null) {
      for (final s in series) {
        for (final p in periods) {
          final v = s.valueSelector(p);
          if (minY == null && v < lo) lo = v;
          if (maxY == null && v > hi) hi = v;
        }
      }
      // Add a little breathing room.
      if (minY == null) lo = (lo - 4).floorToDouble();
      if (maxY == null) hi = (hi + 4).ceilToDouble();
    }

    // Choose a grid interval that gives ~3–5 horizontal lines.
    final range = hi - lo;
    final hInterval = range > 80
        ? 20.0
        : range > 40
            ? 10.0
            : range > 20
                ? 5.0
                : 2.0;

    // Indices where a new calendar day starts (for vertical day-boundary lines).
    final dayBounds = <int>{};
    for (int i = 0; i < periods.length; i++) {
      if (periods[i].startTime.toLocal().hour == 0) dayBounds.add(i);
    }

    final lineBars = series.map((s) {
      final spots = List.generate(
        periods.length,
        (i) => FlSpot(i.toDouble(), s.valueSelector(periods[i])),
      );
      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: s.color,
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    return SizedBox(
      width: periods.length * kPixelsPerHour,
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (periods.length - 1).toDouble(),
          minY: lo,
          maxY: hi,
          lineBarsData: lineBars,
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            verticalInterval: 1.0,
            drawHorizontalLine: true,
            horizontalInterval: hInterval,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: gridColor, strokeWidth: 0.5),
            getDrawingVerticalLine: (value) => dayBounds.contains(value.round())
                ? FlLine(color: gridColor, strokeWidth: 1.0)
                : FlLine(color: gridColor, strokeWidth: 0.5),
          ),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }
}
