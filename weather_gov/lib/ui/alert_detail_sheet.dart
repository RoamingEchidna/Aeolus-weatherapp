import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/weather_alert.dart';

class AlertDetailSheet extends StatelessWidget {
  final List<WeatherAlert> alerts;

  const AlertDetailSheet({super.key, required this.alerts});

  static void show(BuildContext context, List<WeatherAlert> alerts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AlertDetailSheet(alerts: alerts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, MMM d h:mm a');
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.3,
      expand: false,
      builder: (_, controller) => ListView.separated(
        controller: controller,
        padding: const EdgeInsets.all(16),
        itemCount: alerts.length,
        separatorBuilder: (_, __) => const Divider(height: 32),
        itemBuilder: (_, i) {
          final alert = alerts[i];
          final color = WeatherAlert.alertColor(alert.severity);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(alert.event,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 4),
              Text(alert.headline,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('From: ${fmt.format(alert.onset.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall),
              Text('Until: ${fmt.format(alert.expires.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall),
              if (alert.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(alert.description,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (alert.instruction.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('What to do: ${alert.instruction}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic)),
              ],
            ],
          );
        },
      ),
    );
  }
}
