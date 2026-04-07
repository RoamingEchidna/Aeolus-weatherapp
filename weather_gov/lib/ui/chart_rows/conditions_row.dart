import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';

class ConditionsRow extends StatelessWidget {
  final List<HourlyPeriod> periods;

  const ConditionsRow({super.key, required this.periods});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: periods.length * kPixelsPerHour,
      height: kChartRowHeight,
      child: Row(
        children: periods
            .map((p) => SizedBox(
                  width: kPixelsPerHour,
                  height: kChartRowHeight,
                  child: p.iconUrl.isNotEmpty
                      ? Image.network(
                          p.iconUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.cloud, size: 16),
                        )
                      : const Icon(Icons.cloud, size: 16),
                ))
            .toList(),
      ),
    );
  }
}
