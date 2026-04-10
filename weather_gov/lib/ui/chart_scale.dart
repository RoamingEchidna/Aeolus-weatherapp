import 'package:flutter/material.dart';
import '../constants.dart';

/// Provides the current pixels-per-hour scale to all chart widgets in the tree.
/// Use [ChartScale.of(context).pixelsPerHour] instead of the [kPixelsPerHour] constant
/// wherever the value needs to respond to pinch-zoom.
class ChartScale extends InheritedWidget {
  final double pixelsPerHour;

  const ChartScale({
    super.key,
    required this.pixelsPerHour,
    required super.child,
  });

  static ChartScale of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<ChartScale>();
    // Fall back to the default constant if no ancestor is present.
    return result ?? const ChartScale(pixelsPerHour: kPixelsPerHour, child: SizedBox.shrink());
  }

  @override
  bool updateShouldNotify(ChartScale old) => pixelsPerHour != old.pixelsPerHour;
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
