import 'package:flutter/material.dart';
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
          final p = entry.value;
          final hour = p.startTime.toLocal().hour;
          final isStartOfDay = hour == 0 || i == 0;
          String label;
          if (isStartOfDay) {
            label = _dayLabel(p.startTime.toLocal());
          } else if (hour % 6 == 0) {
            label = _hourLabel(hour);
          } else {
            label = '';
          }
          return SizedBox(
            width: kPixelsPerHour,
            child: label.isEmpty
                ? const SizedBox.shrink()
                : Text(label,
                    style: textTheme.labelSmall,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    softWrap: false),
          );
        }).toList(),
      ),
    );
  }

  String _dayLabel(DateTime dt) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[dt.weekday % 7];
  }

  String _hourLabel(int hour) {
    return hour.toString().padLeft(2, '0');
  }
}
