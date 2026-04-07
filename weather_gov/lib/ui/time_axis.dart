import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/hourly_period.dart';

class TimeAxis extends StatelessWidget {
  final List<HourlyPeriod> periods;

  const TimeAxis({super.key, required this.periods});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: kTimeAxisHeight,
      child: Row(
        children: periods.asMap().entries.map((entry) {
          final i = entry.key;
          final period = entry.value;
          final hour = period.startTime.toLocal().hour;
          final isFirstOrMidnight = i == 0 || hour == 0;
          final showSixHour = hour % 6 == 0;

          String? label;
          TextStyle? style;
          if (isFirstOrMidnight) {
            label = DateFormat('EEE').format(period.startTime.toLocal());
            style =
                textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold);
          } else if (showSixHour) {
            label = hour < 12
                ? '${hour}am'
                : hour == 12
                    ? '12pm'
                    : '${hour - 12}pm';
            style = textTheme.labelSmall;
          }

          return SizedBox(
            width: kPixelsPerHour,
            child: label != null
                ? Text(label,
                    style: style,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    softWrap: false)
                : null,
          );
        }).toList(),
      ),
    );
  }
}
