import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/hourly_period.dart';
import 'chart_scale.dart';


class TimeAxis extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final bool use24Hour;

  const TimeAxis({super.key, required this.periods, this.use24Hour = false});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scale = ChartScale.of(context);
    final pph = scale.pixelsPerHour;
    final hourStep = chartHourStep(pph);
    return ClipRect(
      child: SizedBox(
      height: kTimeAxisHeight,
      child: Row(
        children: [
          ...periods.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final localTime = scale.toLocationTime(p.startTime);
            final hour = localTime.hour;
            final isStartOfDay = hour == 0 || i == 0;
            String label;
            if (isStartOfDay) {
              label = _dayLabel(localTime);
            } else if (hour % hourStep == 0) {
              label = _hourLabel(hour, use24Hour);
            } else {
              label = '';
            }
            return SizedBox(
              width: pph,
              child: label.isEmpty
                  ? const SizedBox.shrink()
                  : Text(label,
                      style: textTheme.labelSmall,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                      softWrap: false),
            );
          }),
        ],
      ),
      ),
    );
  }

  String _dayLabel(DateTime dt) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[dt.weekday % 7];
  }

  String _hourLabel(int hour, bool use24Hour) {
    if (use24Hour) return hour.toString().padLeft(2, '0');
    if (hour == 0) return '12a';
    if (hour < 12) return '${hour}a';
    if (hour == 12) return '12p';
    return '${hour - 12}p';
  }
}
