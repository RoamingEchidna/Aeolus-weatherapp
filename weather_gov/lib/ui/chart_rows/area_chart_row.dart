import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';

class AreaChartRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final Color color;
  final double Function(HourlyPeriod) valueSelector;

  const AreaChartRow({
    super.key,
    required this.periods,
    required this.color,
    required this.valueSelector,
  });

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) return const SizedBox(height: kChartRowHeight);

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
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: color,
              isCurved: true,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withAlpha(76), // ~30% opacity
              ),
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
