import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';

class LineChartRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final Color color;
  final double Function(HourlyPeriod) valueSelector;

  const LineChartRow({
    super.key,
    required this.periods,
    required this.color,
    required this.valueSelector,
  });

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) return SizedBox(height: kChartRowHeight);

    final values = periods.map(valueSelector).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b) - 5;
    final maxVal = values.reduce((a, b) => a > b ? a : b) + 5;

    final spots = periods
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), valueSelector(e.value)))
        .toList();

    return SizedBox(
      width: periods.length * kPixelsPerHour,
      height: kChartRowHeight,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (periods.length - 1).toDouble(),
          minY: minVal,
          maxY: maxVal,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: color,
              isCurved: true,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }
}
