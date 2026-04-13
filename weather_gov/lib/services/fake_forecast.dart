import '../models/hourly_period.dart';
import '../models/saved_location.dart';

/// Generates a fake 7-day SavedLocation for UI testing.
/// Weather events (all in location-local hours, UTC-4):
///   Day +1  08-18 : rain_showers (chance, ~0.05"/hr)
///   Day +2  06-16 : snow_showers (likely, ~0.03"/hr) + freezing_rain (slight_chance) 16-20
///   Day +3  14-22 : thunderstorms (definite), thunderPct 70-100
///   Day +4  10-15 : tornadoes (slight_chance)
///   Day +5  08-18 : volcanic_ash (chance)
///   Day +6  00-10 : fog (definite); 12-20 rain (likely, ~0.04"/hr)
SavedLocation buildFakeSavedLocation() {
  const tzOffset = -4; // EDT
  final now = DateTime.now().toUtc();
  // Snap to the current UTC hour so periods line up cleanly.
  final windowStart = DateTime.utc(now.year, now.month, now.day, now.hour);

  final periods = <HourlyPeriod>[];

  for (int i = 0; i < 7 * 24; i++) {
    final utc  = windowStart.add(Duration(hours: i));
    final loc  = utc.add(const Duration(hours: tzOffset)); // local time
    final day  = utc.difference(windowStart).inDays;       // 0-6
    final hour = loc.hour;

    // --- Determine weather types + accumulations for this hour ---
    Map<String, String>? wt;
    double? rainIn;
    double? snowIn;
    int? thunderPct;

    switch (day) {
      case 1: // rain day
        if (hour >= 8 && hour < 18) {
          wt     = {'rain_showers': 'chance'};
          rainIn = 0.05;
        }
        break;

      case 2: // snow day + some freezing rain in the evening
        if (hour >= 6 && hour < 16) {
          wt     = {'snow_showers': 'likely'};
          snowIn = 0.03;
        } else if (hour >= 16 && hour < 20) {
          wt = {'freezing_rain': 'slight_chance'};
        }
        break;

      case 3: // thunderstorm evening
        if (hour >= 14 && hour < 22) {
          wt         = {'thunderstorms': 'definite'};
          thunderPct = 70 + ((hour - 14) * 4).clamp(0, 30);
          if (hour >= 16 && hour < 20) rainIn = 0.08;
        }
        break;

      case 4: // tornado threat mid-day
        if (hour >= 10 && hour < 15) {
          wt = {'tornadoes': 'slight_chance'};
          // some rain accompanies the threat
          rainIn     = 0.03;
          thunderPct = 40;
        }
        break;

      case 5: // volcanic ash drifting through
        if (hour >= 8 && hour < 18) {
          wt = {'volcanic_ash': 'chance'};
        }
        break;

      case 6: // foggy morning, rainy afternoon
        if (hour >= 0 && hour < 10) {
          wt = {'fog': 'definite'};
        } else if (hour >= 12 && hour < 20) {
          wt     = {'rain': 'likely'};
          rainIn = 0.04;
        }
        break;
    }

    // Sensible baseline values for the non-weather fields.
    final tempF = 55 - day * 2 + (hour >= 14 ? 8 : (hour >= 8 ? 4 : 0));

    periods.add(HourlyPeriod(
      startTime:        utc,
      temperature:      tempF,
      precipChance:     wt != null ? 60 : 5,
      relativeHumidity: wt != null ? 85 : 40,
      dewpointF:        tempF - 15.0,
      windSpeedMph:     8 + (day * 2).toDouble(),
      windDirection:    ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W'][day % 7],
      shortForecast:    wt != null ? 'Various' : 'Partly Cloudy',
      iconUrl:          'https://api.weather.gov/icons/land/day/few',
      thunderPct:       thunderPct,
      rainInches:       rainIn,
      snowInches:       snowIn,
      weatherTypes:     wt,
    ));
  }

  final now2 = DateTime.now();
  return SavedLocation(
    displayName:    'Narnia',
    lat:            40.0,
    lon:            -75.0,
    lastAccessed:   now2,
    cachedForecast: periods,
    cachedAlerts:   [],
    cacheTimestamp: now2,
    cachedAstroData: [],
    isPinned:       false,
    tzOffsetHours:  tzOffset,
    timeZone:       'America/New_York',
  );
}
