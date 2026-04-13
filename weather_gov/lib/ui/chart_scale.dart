import 'package:flutter/material.dart';
import '../constants.dart';

/// Provides the current pixels-per-hour scale and location timezone offset
/// to all chart widgets in the tree.
class ChartScale extends InheritedWidget {
  final double pixelsPerHour;
  /// UTC offset in whole hours for the displayed location (e.g. -7 for PDT).
  final int tzOffsetHours;

  const ChartScale({
    super.key,
    required this.pixelsPerHour,
    this.tzOffsetHours = 0,
    required super.child,
  });

  static ChartScale of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<ChartScale>();
    return result ?? const ChartScale(pixelsPerHour: kPixelsPerHour, child: SizedBox.shrink());
  }

  /// Converts a UTC DateTime to the location's local time.
  DateTime toLocationTime(DateTime utc) =>
      utc.toUtc().add(Duration(hours: tzOffsetHours));

  @override
  bool updateShouldNotify(ChartScale old) =>
      pixelsPerHour != old.pixelsPerHour || tzOffsetHours != old.tzOffsetHours;
}

/// Returns how many hours apart vertical grid lines should be drawn,
/// targeting at least ~20px of space between them.
/// Snaps to "nice" intervals: 1, 2, 3, 6, 12, 24.
int chartHourStep(double pixelsPerHour) {
  const minSpacing = 20.0;
  final raw = minSpacing / pixelsPerHour;
  if (raw <= 1)  return 1;
  if (raw <= 2)  return 2;
  if (raw <= 3)  return 3;
  if (raw <= 6)  return 6;
  if (raw <= 12) return 12;
  return 24;
}
