import 'hourly_period.dart';
import 'weather_alert.dart';
import 'astro_day.dart';

class SavedLocation {
  final String displayName;
  final double lat;
  final double lon;
  final DateTime lastAccessed;
  final List<HourlyPeriod> cachedForecast;
  final List<WeatherAlert> cachedAlerts;
  final DateTime cacheTimestamp;
  final List<AstroDay> cachedAstroData;
  final bool isPinned;
  final String? postcode;

  const SavedLocation({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.lastAccessed,
    required this.cachedForecast,
    required this.cachedAlerts,
    required this.cacheTimestamp,
    this.cachedAstroData = const [],
    this.isPinned = false,
    this.postcode,
  });

  SavedLocation copyWith({
    String? displayName,
    double? lat,
    double? lon,
    DateTime? lastAccessed,
    List<HourlyPeriod>? cachedForecast,
    List<WeatherAlert>? cachedAlerts,
    DateTime? cacheTimestamp,
    List<AstroDay>? cachedAstroData,
    bool? isPinned,
    String? postcode,
  }) {
    return SavedLocation(
      displayName: displayName ?? this.displayName,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      cachedForecast: cachedForecast ?? this.cachedForecast,
      cachedAlerts: cachedAlerts ?? this.cachedAlerts,
      cacheTimestamp: cacheTimestamp ?? this.cacheTimestamp,
      cachedAstroData: cachedAstroData ?? this.cachedAstroData,
      isPinned: isPinned ?? this.isPinned,
      postcode: postcode ?? this.postcode,
    );
  }

  factory SavedLocation.fromJson(Map<String, dynamic> json) {
    return SavedLocation(
      displayName: json['displayName'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      cachedForecast: (json['cachedForecast'] as List<dynamic>)
          .map((e) => HourlyPeriod.fromStoredJson(e as Map<String, dynamic>))
          .toList(),
      cachedAlerts: (json['cachedAlerts'] as List<dynamic>)
          .map((e) => WeatherAlert.fromStoredJson(e as Map<String, dynamic>))
          .toList(),
      cacheTimestamp: DateTime.parse(json['cacheTimestamp'] as String),
      cachedAstroData: json.containsKey('cachedAstroData')
          ? (json['cachedAstroData'] as List<dynamic>)
              .map((e) => AstroDay.fromStoredJson(e as Map<String, dynamic>))
              .toList()
          : [],
      isPinned: json.containsKey('isPinned') && json['isPinned'] == true,
      postcode: json['postcode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'lat': lat,
        'lon': lon,
        'lastAccessed': lastAccessed.toIso8601String(),
        'cachedForecast': cachedForecast.map((p) => p.toJson()).toList(),
        'cachedAlerts': cachedAlerts.map((a) => a.toJson()).toList(),
        'cacheTimestamp': cacheTimestamp.toIso8601String(),
        'cachedAstroData': cachedAstroData.map((d) => d.toJson()).toList(),
        'isPinned': isPinned,
        if (postcode != null) 'postcode': postcode,
      };
}
