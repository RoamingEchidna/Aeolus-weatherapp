double parseWindSpeed(String windSpeedStr) {
  final rangeMatch = RegExp(r'(\d+)\s+to\s+(\d+)').firstMatch(windSpeedStr);
  if (rangeMatch != null) {
    final low = double.parse(rangeMatch.group(1)!);
    final high = double.parse(rangeMatch.group(2)!);
    return (low + high) / 2;
  }
  final singleMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(windSpeedStr);
  return singleMatch != null ? double.parse(singleMatch.group(1)!) : 0.0;
}

double celsiusToFahrenheit(double celsius) => celsius * 9 / 5 + 32;

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

  // Parse from NWS API hourly period JSON
  factory HourlyPeriod.fromJson(Map<String, dynamic> json) {
    return HourlyPeriod(
      startTime: DateTime.parse(json['startTime'] as String),
      temperature: json['temperature'] as int,
      precipChance:
          (json['probabilityOfPrecipitation']?['value'] as num?)?.toInt() ?? 0,
      relativeHumidity:
          (json['relativeHumidity']?['value'] as num?)?.toInt() ?? 0,
      dewpointF: celsiusToFahrenheit(
          (json['dewpoint']?['value'] as num?)?.toDouble() ?? 0.0),
      windSpeedMph: parseWindSpeed(json['windSpeed'] as String? ?? '0 mph'),
      windDirection: json['windDirection'] as String? ?? '',
      shortForecast: json['shortForecast'] as String? ?? '',
      iconUrl: json['icon'] as String? ?? '',
    );
  }

  // Parse from our own cache storage JSON
  factory HourlyPeriod.fromStoredJson(Map<String, dynamic> json) {
    return HourlyPeriod(
      startTime: DateTime.parse(json['startTime'] as String),
      temperature: json['temperature'] as int,
      precipChance: json['precipChance'] as int,
      relativeHumidity: json['relativeHumidity'] as int,
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
