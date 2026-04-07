import 'dart:math';
import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';

const _cardinalDegrees = <String, double>{
  'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5,
  'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
  'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5,
  'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
};

class WindDirectionRow extends StatelessWidget {
  final List<HourlyPeriod> periods;

  const WindDirectionRow({super.key, required this.periods});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: periods.length * kPixelsPerHour,
      height: kChartRowHeight,
      child: Row(
        children: periods.map((p) {
          final degrees = _cardinalDegrees[p.windDirection] ?? 0.0;
          final radians = degrees * pi / 180;
          return SizedBox(
            width: kPixelsPerHour,
            height: kChartRowHeight,
            child: Center(
              child: Transform.rotate(
                angle: radians,
                child: const Icon(
                  Icons.arrow_upward,
                  size: kPixelsPerHour * 0.75,
                  color: kColorWindDirection,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
