class AstroDay {
  final DateTime date; // midnight local time for this calendar day
  final DateTime? beginCivilTwilight;
  final DateTime? sunrise;
  final DateTime? solarNoon;
  final DateTime? sunset;
  final DateTime? endCivilTwilight;
  final DateTime? moonrise;
  final DateTime? moonset;
  final int? uvIndex;
  final String? moonPhase; // e.g. "Waxing Crescent", "Full Moon", etc.

  const AstroDay({
    required this.date,
    this.beginCivilTwilight,
    this.sunrise,
    this.solarNoon,
    this.sunset,
    this.endCivilTwilight,
    this.moonrise,
    this.moonset,
    this.uvIndex,
    this.moonPhase,
  });

  AstroDay copyWith({int? uvIndex, String? moonPhase}) => AstroDay(
        date: date,
        beginCivilTwilight: beginCivilTwilight,
        sunrise: sunrise,
        solarNoon: solarNoon,
        sunset: sunset,
        endCivilTwilight: endCivilTwilight,
        moonrise: moonrise,
        moonset: moonset,
        uvIndex: uvIndex ?? this.uvIndex,
        moonPhase: moonPhase ?? this.moonPhase,
      );

  /// A sentinel value representing a failed API call for this date.
  /// All event fields are null; painter draws diagonal hatching.
  factory AstroDay.sentinel(DateTime date) => AstroDay(date: date);

  bool get isSentinel =>
      beginCivilTwilight == null &&
      sunrise == null &&
      solarNoon == null &&
      sunset == null &&
      endCivilTwilight == null &&
      moonrise == null &&
      moonset == null;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'beginCivilTwilight': beginCivilTwilight?.toIso8601String(),
        'sunrise': sunrise?.toIso8601String(),
        'solarNoon': solarNoon?.toIso8601String(),
        'sunset': sunset?.toIso8601String(),
        'endCivilTwilight': endCivilTwilight?.toIso8601String(),
        'moonrise': moonrise?.toIso8601String(),
        'moonset': moonset?.toIso8601String(),
        if (uvIndex != null) 'uvIndex': uvIndex,
        if (moonPhase != null) 'moonPhase': moonPhase,
      };

  factory AstroDay.fromStoredJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final s = json[key] as String?;
      return s == null ? null : DateTime.parse(s);
    }

    return AstroDay(
      date: DateTime.parse(json['date'] as String),
      beginCivilTwilight: parse('beginCivilTwilight'),
      sunrise: parse('sunrise'),
      solarNoon: parse('solarNoon'),
      sunset: parse('sunset'),
      endCivilTwilight: parse('endCivilTwilight'),
      moonrise: parse('moonrise'),
      moonset: parse('moonset'),
      uvIndex: json['uvIndex'] as int?,
      moonPhase: json['moonPhase'] as String?,
    );
  }
}
