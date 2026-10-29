import 'package:flutter/material.dart';
import '../constants.dart';
import 'chart_row_entries.dart';

/// Legend boxes pinned to the top-right corner of each graph row. Stays put
/// while the chart scrolls sideways.
class RowLegendOverlay extends StatelessWidget {
  final List<ChartRowEntry> rows;

  const RowLegendOverlay({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    double legendTop = 0;
    final legendPositioned = <Widget>[];
    for (final entry in rows) {
      if (entry.legendItems.isNotEmpty) {
        final top = legendTop;
        legendPositioned.add(Positioned(
          top: top + 4,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: surfaceColor.withAlpha(180),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: entry.legendItems
                  .map((item) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 10, height: 10, color: item.color),
                          const SizedBox(width: 4),
                          Text(item.label, style: textTheme.labelSmall),
                        ],
                      ))
                  .toList(),
            ),
          ),
        ));
      }
      legendTop += entry.height;
    }
    return IgnorePointer(
      child: Stack(children: legendPositioned),
    );
  }
}

/// Y-axis value labels pinned to the left edge of each row that has a
/// numeric scale. Stays put while the chart scrolls sideways.
class YAxisLabelOverlay extends StatelessWidget {
  final List<ChartRowEntry> rows;

  const YAxisLabelOverlay({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.map((entry) {
          if (entry.minY == null) {
            return SizedBox(height: entry.height);
          }
          final first =
              (entry.minY! / entry.hInterval!).ceil() * entry.hInterval!;
          final labelWidgets = <Widget>[];
          for (double v = first;
              v <= entry.maxY! + 0.001;
              v += entry.hInterval!) {
            if (entry.hideEndLabels &&
                (v <= entry.minY! + 0.001 || v >= entry.maxY! - 0.001)) {
              continue;
            }
            final t = entry.height *
                (1.0 - (v - entry.minY!) / (entry.maxY! - entry.minY!));
            final clampedTop = (t - 6).clamp(0.0, entry.height - 12.0);
            labelWidgets.add(Positioned(
              left: 4,
              top: clampedTop,
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor.withAlpha(180),
                  borderRadius: BorderRadius.circular(2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '${v.round()}${entry.unit}',
                  style: textTheme.labelSmall,
                ),
              ),
            ));
          }
          return SizedBox(
            height: entry.height,
            width: kLabelColumnWidth,
            child: Stack(clipBehavior: Clip.hardEdge, children: labelWidgets),
          );
        }).toList(),
      ),
    );
  }
}
