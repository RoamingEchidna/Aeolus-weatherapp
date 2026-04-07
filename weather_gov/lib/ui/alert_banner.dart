import 'package:flutter/material.dart';
import '../models/weather_alert.dart';
import 'alert_detail_sheet.dart';

class AlertBanner extends StatelessWidget {
  final List<WeatherAlert> alerts;

  const AlertBanner({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    final severityOrder = ['Extreme', 'Severe', 'Moderate', 'Minor'];
    final topAlert = alerts.reduce((a, b) {
      final ai = severityOrder.indexOf(a.severity);
      final bi = severityOrder.indexOf(b.severity);
      return (ai <= bi) ? a : b;
    });

    final color = WeatherAlert.alertColor(topAlert.severity);
    final label = alerts.length == 1
        ? topAlert.headline
        : '${alerts.length} active alerts — tap to view';

    return GestureDetector(
      onTap: () => AlertDetailSheet.show(context, alerts),
      child: Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white),
        ]),
      ),
    );
  }
}
