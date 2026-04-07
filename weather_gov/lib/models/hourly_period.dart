import 'dart:math';

class HourlyPeriod {
  final DateTime startTime;
  final int temperature;
  final int precipChance;
  final int relativeHumidity;
  final double dewpointF;
  final double windSpeedMph;
  final String windDirection;
  final String shortForecast;
  final String iconUrl;

  const HourlyPeriod({
    required this.startTime,
    required this.temperature,
    required this.precipChance,
    required this.relativeHumidity,
    required this.dewpointF,
    required this.windSpeedMph,
    required this.windDirection,
    required this.shortForecast,
    required this.iconUrl,
  });

  // Wind chill formula (NWS). Only valid when T <= 50°F and V > 3 mph.
  double get windChillF {
    final t = temperature.toDouble();
    if (t > 50 || windSpeedMph <= 3) return t;
    final v = windSpeedMph;
    return 35.74 +
        0.6215 * t -
        35.75 * pow(v, 0.16) +
        0.4275 * t * pow(v, 0.16);
  }

  // Sky cover percentage derived from NWS icon URL codes.
  int get skyCoverPct {
    final uri = Uri.tryParse(iconUrl);
    if (uri != null) {
      for (final seg in uri.pathSegments) {
        final base = seg.split(',').first.toLowerCase();
        switch (base) {
          case 'skc':
          case 'hot':
          case 'cold':
            return 5;
          case 'few':
            return 15;
          case 'sct':
            return 40;
          case 'bkn':
            return 70;
          case 'ovc':
          case 'fog':
            return 95;
        }
      }
    }
    // Fallback: parse shortForecast text
    final f = shortForecast.toLowerCase();
    if (f.contains('mostly clear') || f.contains('mostly sunny')) return 20;
    if (f.contains('partly')) return 40;
    if (f.contains('mostly cloudy')) return 70;
    if (f.contains('overcast') || f.contains('fog')) return 95;
    if (f.contains('cloudy')) return 85;
    return 5;
  }

  static double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;

  static double parseWindSpeed(String raw) {
    final rangeMatch = RegExp(r'(\d+)\s+to\s+(\d+)').firstMatch(raw);
    if (rangeMatch != null) {
      final lo = double.parse(rangeMatch.group(1)!);
      final hi = double.parse(rangeMatch.group(2)!);
      return (lo + hi) / 2;
    }
    final singleMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
    return singleMatch != null ? double.parse(singleMatch.group(1)!) : 0.0;
  }

  factory HourlyPeriod.fromJson(Map<String, dynamic> json) {
    final dewpointC =
        ((json['dewpoint'] as Map<String, dynamic>)['value'] as num?)
                ?.toDouble() ??
            0.0;
    final precip =
        ((json['probabilityOfPrecipitation'] as Map<String, dynamic>)['value']
                as num?)
            ?.toInt() ??
        0;
    final humidity =
        ((json['relativeHumidity'] as Map<String, dynamic>)['value'] as num?)
                ?.toInt() ??
            0;
    return HourlyPeriod(
      startTime: DateTime.parse(json['startTime'] as String),
      temperature: (json['temperature'] as num).toInt(),
      precipChance: precip,
      relativeHumidity: humidity,
      dewpointF: celsiusToFahrenheit(dewpointC),
      windSpeedMph: parseWindSpeed(json['windSpeed'] as String? ?? '0 mph'),
      windDirection: json['windDirection'] as String? ?? '',
      shortForecast: json['shortForecast'] as String? ?? '',
      iconUrl: json['icon'] as String? ?? '',
    );
  }

  factory HourlyPeriod.fromStoredJson(Map<String, dynamic> json) {
    return HourlyPeriod(
      startTime: DateTime.parse(json['startTime'] as String),
      temperature: (json['temperature'] as num).toInt(),
      precipChance: (json['precipChance'] as num).toInt(),
      relativeHumidity: (json['relativeHumidity'] as num).toInt(),
      dewpointF: (json['dewpointF'] as num).toDouble(),
      windSpeedMph: (json['windSpeedMph'] as num).toDouble(),
      windDirection: json['windDirection'] as String,
      shortForecast: json['shortForecast'] as String,
      iconUrl: json['iconUrl'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'startTime': startTime.toIso8601String(),
        'temperature': temperature,
        'precipChance': precipChance,
        'relativeHumidity': relativeHumidity,
        'dewpointF': dewpointF,
        'windSpeedMph': windSpeedMph,
        'windDirection': windDirection,
        'shortForecast': shortForecast,
        'iconUrl': iconUrl,
      };
}
