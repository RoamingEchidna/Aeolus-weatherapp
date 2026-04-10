import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/hourly_period.dart';
import '../chart_scale.dart';

class ConditionsRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final double height;

  const ConditionsRow(
      {super.key, required this.periods, this.height = kChartRowHeight});

  Color _colorFor(String forecast, Brightness brightness) {
    final f = forecast.toLowerCase();
    if (f.contains('thunder')) return adaptiveChartColor(kColorWeatherThunder, brightness);
    if (f.contains('freezing')) return adaptiveChartColor(kColorWeatherFreezingRain, brightness);
    if (f.contains('sleet') || f.contains('ice pellet')) return adaptiveChartColor(kColorWeatherSleet, brightness);
    if (f.contains('snow') || f.contains('blizzard')) return adaptiveChartColor(kColorWeatherSnow, brightness);
    if (f.contains('rain') || f.contains('shower') || f.contains('drizzle')) {
      return adaptiveChartColor(kColorWeatherRain, brightness);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final borderColor = Theme.of(context).colorScheme.outline.withAlpha(120);
    final textStyle = Theme.of(context)
        .textTheme
        .labelSmall!
        .copyWith(fontWeight: FontWeight.bold);

    // Group consecutive periods with the same shortForecast.
    final groups = <({String label, int count})>[];
    for (final p in periods) {
      if (groups.isEmpty || groups.last.label != p.shortForecast) {
        groups.add((label: p.shortForecast, count: 1));
      } else {
        final last = groups.removeLast();
        groups.add((label: last.label, count: last.count + 1));
      }
    }

    final pph = ChartScale.of(context).pixelsPerHour;
    return SizedBox(
      width: periods.length * pph,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: groups
            .map((g) => _ConditionCell(
                  label: g.label,
                  width: g.count * pph,
                  height: height,
                  color: _colorFor(g.label, brightness),
                  borderColor: borderColor,
                  textStyle: textStyle,
                ))
            .toList(),
      ),
    );
  }
}

class _ConditionCell extends StatefulWidget {
  final String label;
  final double width;
  final double height;
  final Color color;
  final Color borderColor;
  final TextStyle textStyle;

  const _ConditionCell({
    required this.label,
    required this.width,
    required this.height,
    required this.color,
    required this.borderColor,
    required this.textStyle,
  });

  @override
  State<_ConditionCell> createState() => _ConditionCellState();
}

class _ConditionCellState extends State<_ConditionCell> {
  OverlayEntry? _overlay;

  void _showOverlay(TapDownDetails details) {
    _removeOverlay();

    // Capture theme info before entering the overlay builder.
    final colorScheme = Theme.of(context).colorScheme;
    final bodyStyle = Theme.of(context).textTheme.bodySmall!;
    final screenWidth = MediaQuery.of(context).size.width;
    final pos = details.globalPosition;

    const tooltipWidth = 200.0;
    const tooltipOffset = 90.0; // dp above tap center to clear the finger

    final left = (pos.dx - tooltipWidth / 2).clamp(8.0, screenWidth - tooltipWidth - 8.0);
    final top = pos.dy - tooltipOffset;

    _overlay = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _removeOverlay,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.inverseSurface,
                child: Container(
                  width: tooltipWidth,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    widget.label,
                    style: bodyStyle.copyWith(
                        color: colorScheme.onInverseSurface),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return GestureDetector(
      onTapDown: _showOverlay,
      onTapUp: (_) =>
          Future.delayed(const Duration(milliseconds: 500), _removeOverlay),
      onTapCancel: () =>
          Future.delayed(const Duration(milliseconds: 500), _removeOverlay),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          border: Border.all(color: widget.borderColor, width: 0.5),
          color: color == Colors.transparent ? null : color.withAlpha(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: color == Colors.transparent
              ? widget.textStyle
              : widget.textStyle.copyWith(color: color),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }
}
