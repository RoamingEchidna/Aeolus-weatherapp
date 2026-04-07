import 'package:flutter/material.dart';
import '../constants.dart';

class WeatherAlert {
  final String event;
  final String severity;
  final String headline;
  final String description;
  final String instruction;
  final DateTime onset;
  final DateTime expires;

  const WeatherAlert({
    required this.event,
    required this.severity,
    required this.headline,
    required this.description,
    required this.instruction,
    required this.onset,
    required this.expires,
  });

  factory WeatherAlert.fromJson(Map<String, dynamic> json) {
    final props = json['properties'] as Map<String, dynamic>;
    final onsetStr = props['onset'] as String? ?? props['effective'] as String;
    return WeatherAlert(
      event: props['event'] as String? ?? '',
      severity: props['severity'] as String? ?? 'Unknown',
      headline: props['headline'] as String? ?? '',
      description: props['description'] as String? ?? '',
      instruction: props['instruction'] as String? ?? '',
      onset: DateTime.parse(onsetStr),
      expires: DateTime.parse(props['expires'] as String),
    );
  }

  factory WeatherAlert.fromStoredJson(Map<String, dynamic> json) {
    return WeatherAlert(
      event: json['event'] as String,
      severity: json['severity'] as String,
      headline: json['headline'] as String,
      description: json['description'] as String,
      instruction: json['instruction'] as String,
      onset: DateTime.parse(json['onset'] as String),
      expires: DateTime.parse(json['expires'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'event': event,
        'severity': severity,
        'headline': headline,
        'description': description,
        'instruction': instruction,
        'onset': onset.toIso8601String(),
        'expires': expires.toIso8601String(),
      };

  static Color alertColor(String severity) {
    switch (severity) {
      case 'Extreme':
      case 'Severe':
        return kColorAlertExtreme;
      case 'Minor':
        return kColorAlertMinor;
      default:
        return kColorAlertModerate;
    }
  }
}
