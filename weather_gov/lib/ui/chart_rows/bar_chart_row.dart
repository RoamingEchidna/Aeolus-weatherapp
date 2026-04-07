import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';

class BarChartRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final Color color;
  final double Function(HourlyPeriod) valueSelector;
  final double maxY;

  const BarChartRow({
    super.key,
    required this.periods,
    required this.color,
    required this.valueSelector,
    this.maxY = 100,
  });

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) return const SizedBox(height: kChartRowHeight);

    return SizedBox(
      width: periods.length * kPixelsPerHour,
      height: kChartRowHeight,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          barGroups: periods
              .asMap()
              .entries
              .map((e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: valueSelector(e.value),
                        color: color,
                        width: kPixelsPerHour * 0.75,
                        borderRadius: BorderRadius.zero,
                      ),
                    ],
                  ))
              .toList(),
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
        ),
      ),
    );
  }
}
