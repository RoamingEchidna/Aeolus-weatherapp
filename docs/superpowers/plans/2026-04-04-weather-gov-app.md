# Weather.gov Scrollable Forecast App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter Android app that displays the NWS 7-day hourly forecast as a horizontally scrollable multi-row chart with location search, row toggles, alert banners, and offline caching.

**Architecture:** A single `ForecastProvider` (ChangeNotifier) holds all state and coordinates three services (NominatimService, NwsService, CacheService). The UI is one screen — a `Scaffold` with a pinned `AppBar`, an optional `AlertBanner`, and a `ScrollableChart` — plus a slide-out `AppDrawer`.

**Tech Stack:** Flutter (Dart), Material 3, `provider`, `fl_chart`, `shared_preferences`, `http`, `intl`

---

## File Map

```
weather_gov/
├── pubspec.yaml
├── android/app/src/main/AndroidManifest.xml   (add INTERNET permission)
├── lib/
│   ├── main.dart                              App entry, theme, Provider setup
│   ├── constants.dart                         Layout constants (pixel widths, heights, colors)
│   ├── models/
│   │   ├── hourly_period.dart                 HourlyPeriod + JSON + wind/dewpoint helpers
│   │   ├── weather_alert.dart                 WeatherAlert + JSON
│   │   └── saved_location.dart                SavedLocation + JSON
│   ├── services/
│   │   ├── nominatim_service.dart             City name → lat/lon
│   │   ├── nws_service.dart                   lat/lon → forecast + alerts
│   │   └── cache_service.dart                 SharedPreferences read/write for 10 locations
│   ├── providers/
│   │   └── forecast_provider.dart             All app state, orchestrates services
│   └── ui/
│       ├── chart_screen.dart                  Main Scaffold wiring all UI pieces
│       ├── app_drawer.dart                    Slide-out menu (search, past locations, toggles)
│       ├── alert_banner.dart                  Colored alert strip + tap to expand
│       ├── alert_detail_sheet.dart            Bottom sheet with full alert details
│       ├── scrollable_chart.dart              Pinned labels + single-scroll chart container
│       ├── time_axis.dart                     Hour/day label row at top of chart
│       └── chart_rows/
│           ├── line_chart_row.dart            Temperature & Dewpoint
│           ├── bar_chart_row.dart             Precip Chance & Wind Speed
│           ├── area_chart_row.dart            Humidity
│           ├── wind_direction_row.dart        Rotated arrow icons
│           └── conditions_row.dart            NWS icon images
└── test/
    ├── models/
    │   ├── hourly_period_test.dart
    │   ├── weather_alert_test.dart
    │   └── saved_location_test.dart
    ├── services/
    │   ├── nominatim_service_test.dart
    │   ├── nws_service_test.dart
    │   └── cache_service_test.dart
    └── providers/
        └── forecast_provider_test.dart
```

---

## Task 1: Flutter Project Setup

**Files:**
- Create: `weather_gov/` (Flutter project root)
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Install Flutter SDK**

  Download and install from https://docs.flutter.dev/get-started/install/windows/android
  Then verify:
  ```bash
  flutter doctor
  ```
  Expected: All Android toolchain checks pass (you may see warnings about Xcode — ignore those, this is Android-only).

- [ ] **Step 2: Create the Flutter project**

  ```bash
  cd "c:/Users/Jacob Dunning/Documents/Coding Projects/Weather Gov"
  flutter create --org com.weathergov --platforms android weather_gov
  cd weather_gov
  ```

- [ ] **Step 3: Replace pubspec.yaml dependencies**

  Open `pubspec.yaml` and replace the `dependencies` and `dev_dependencies` sections with:

  ```yaml
  dependencies:
    flutter:
      sdk: flutter
    provider: ^6.1.2
    fl_chart: ^0.68.0
    shared_preferences: ^2.3.2
    http: ^1.2.1
    intl: ^0.19.0

  dev_dependencies:
    flutter_test:
      sdk: flutter
    flutter_lints: ^4.0.0
  ```

  Then run:
  ```bash
  flutter pub get
  ```
  Expected: `Got dependencies!`

- [ ] **Step 4: Add INTERNET permission to AndroidManifest**

  Open `android/app/src/main/AndroidManifest.xml`. Add this line just before the `<application` tag:

  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```

- [ ] **Step 5: Delete the default counter app**

  Replace the entire contents of `lib/main.dart` with:

  ```dart
  import 'package:flutter/material.dart';

  void main() {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Setup OK')))));
  }
  ```

- [ ] **Step 6: Verify the project builds**

  ```bash
  flutter build apk --debug
  ```
  Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 7: Commit**

  ```bash
  git init
  git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml lib/main.dart
  git commit -m "chore: flutter project scaffold with dependencies"
  ```

---

## Task 2: Constants

**Files:**
- Create: `lib/constants.dart`

- [ ] **Step 1: Create constants.dart**

  ```dart
  // lib/constants.dart
  import 'package:flutter/material.dart';

  // Layout
  const double kPixelsPerHour = 24.0;
  const double kChartRowHeight = 80.0;
  const double kTimeAxisHeight = 32.0;
  const double kLabelColumnWidth = 84.0;
  const int kMaxSavedLocations = 10;

  // Chart colors (constant in light and dark mode)
  const Color kColorTemperature   = Color(0xFFFF0000);
  const Color kColorDewpoint      = Color(0xFF00AA00);
  const Color kColorPrecip        = Color(0xFF4DA6FF);
  const Color kColorHumidity      = Color(0xFF00CCCC);
  const Color kColorWindSpeed     = Color(0xFF0000CC);
  const Color kColorWindDirection = Color(0xFF888888);

  // Alert severity colors
  const Color kColorAlertExtreme  = Color(0xFFD32F2F);
  const Color kColorAlertSevere   = Color(0xFFD32F2F);
  const Color kColorAlertModerate = Color(0xFFF57C00);
  const Color kColorAlertMinor    = Color(0xFFF9A825);

  // Row names (used as keys in visibleRows map)
  const String kRowTemperature   = 'Temperature';
  const String kRowDewpoint      = 'Dewpoint';
  const String kRowPrecip        = 'Precip. Chance';
  const String kRowHumidity      = 'Humidity';
  const String kRowWindSpeed     = 'Wind Speed';
  const String kRowWindDirection = 'Wind Direction';
  const String kRowConditions    = 'Conditions';

  const List<String> kAllRows = [
    kRowTemperature,
    kRowDewpoint,
    kRowPrecip,
    kRowHumidity,
    kRowWindSpeed,
    kRowWindDirection,
    kRowConditions,
  ];

  const Map<String, bool> kDefaultRowVisibility = {
    kRowTemperature:   true,
    kRowDewpoint:      false,
    kRowPrecip:        true,
    kRowHumidity:      true,
    kRowWindSpeed:     true,
    kRowWindDirection: true,
    kRowConditions:    true,
  };
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add lib/constants.dart
  git commit -m "chore: add layout and color constants"
  ```

---

## Task 3: Model — HourlyPeriod

**Files:**
- Create: `lib/models/hourly_period.dart`
- Create: `test/models/hourly_period_test.dart`

- [ ] **Step 1: Write the failing tests**

  ```dart
  // test/models/hourly_period_test.dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:weather_gov/models/hourly_period.dart';

  void main() {
    group('parseWindSpeed', () {
      test('parses single value', () {
        expect(parseWindSpeed('3 mph'), 3.0);
      });

      test('averages a range', () {
        expect(parseWindSpeed('10 to 15 mph'), 12.5);
      });

      test('returns 0 for empty/unknown', () {
        expect(parseWindSpeed('Calm'), 0.0);
      });
    });

    group('celsiusToFahrenheit', () {
      test('converts 0C to 32F', () {
        expect(celsiusToFahrenheit(0), 32.0);
      });

      test('converts 100C to 212F', () {
        expect(celsiusToFahrenheit(100), 212.0);
      });
    });

    group('HourlyPeriod.fromJson', () {
      test('parses all fields from API response', () {
        final json = {
          'startTime': '2026-04-04T21:00:00-07:00',
          'temperature': 58,
          'probabilityOfPrecipitation': {'unitCode': 'wmoUnit:percent', 'value': 10},
          'relativeHumidity': {'unitCode': 'wmoUnit:percent', 'value': 17},
          'dewpoint': {'unitCode': 'wmoUnit:degC', 'value': -10.56},
          'windSpeed': '3 mph',
          'windDirection': 'S',
          'shortForecast': 'Partly Cloudy',
          'icon': 'https://api.weather.gov/icons/land/night/few?size=small',
        };

        final period = HourlyPeriod.fromJson(json);

        expect(period.temperature, 58);
        expect(period.precipChance, 10);
        expect(period.relativeHumidity, 17);
        expect(period.dewpointF, closeTo(celsiusToFahrenheit(-10.56), 0.01));
        expect(period.windSpeedMph, 3.0);
        expect(period.windDirection, 'S');
        expect(period.shortForecast, 'Partly Cloudy');
        expect(period.iconUrl, contains('api.weather.gov'));
      });

      test('handles null precipitation and humidity values', () {
        final json = {
          'startTime': '2026-04-04T21:00:00-07:00',
          'temperature': 50,
          'probabilityOfPrecipitation': {'unitCode': 'wmoUnit:percent', 'value': null},
          'relativeHumidity': {'unitCode': 'wmoUnit:percent', 'value': null},
          'dewpoint': {'unitCode': 'wmoUnit:degC', 'value': null},
          'windSpeed': 'Calm',
          'windDirection': 'N',
          'shortForecast': 'Clear',
          'icon': '',
        };

        final period = HourlyPeriod.fromJson(json);
        expect(period.precipChance, 0);
        expect(period.relativeHumidity, 0);
        expect(period.windSpeedMph, 0.0);
      });
    });

    group('HourlyPeriod JSON round-trip', () {
      test('toJson → fromJson preserves values', () {
        final original = HourlyPeriod(
          startTime: DateTime.parse('2026-04-04T21:00:00.000'),
          temperature: 58,
          precipChance: 10,
          relativeHumidity: 17,
          dewpointF: 12.99,
          windSpeedMph: 3.0,
          windDirection: 'S',
          shortForecast: 'Partly Cloudy',
          iconUrl: 'https://example.com/icon.png',
        );

        final restored = HourlyPeriod.fromStoredJson(original.toJson());
        expect(restored.temperature, original.temperature);
        expect(restored.precipChance, original.precipChance);
        expect(restored.windSpeedMph, original.windSpeedMph);
        expect(restored.startTime, original.startTime);
      });
    });
  }
  ```

- [ ] **Step 2: Run tests to confirm they fail**

  ```bash
  flutter test test/models/hourly_period_test.dart
  ```
  Expected: FAIL — `Target of URI doesn't exist: 'package:weather_gov/models/hourly_period.dart'`

- [ ] **Step 3: Implement HourlyPeriod**

  ```dart
  // lib/models/hourly_period.dart

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
            (json['probabilityOfPrecipitation']?['value'] as num?)?.toInt() ??
                0,
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
  ```

- [ ] **Step 4: Run tests — confirm they pass**

  ```bash
  flutter test test/models/hourly_period_test.dart
  ```
  Expected: All tests PASS

- [ ] **Step 5: Commit**

  ```bash
  git add lib/models/hourly_period.dart test/models/hourly_period_test.dart
  git commit -m "feat: add HourlyPeriod model with wind speed parser and dewpoint conversion"
  ```

---

## Task 4: Model — WeatherAlert

**Files:**
- Create: `lib/models/weather_alert.dart`
- Create: `test/models/weather_alert_test.dart`

- [ ] **Step 1: Write the failing tests**

  ```dart
  // test/models/weather_alert_test.dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:weather_gov/models/weather_alert.dart';

  void main() {
    group('WeatherAlert.fromJson', () {
      test('parses all fields from NWS alert feature', () {
        final json = {
          'properties': {
            'event': 'Flood Watch',
            'severity': 'Moderate',
            'headline': 'Flood Watch in effect until 8 PM PDT',
            'description': 'Heavy rainfall expected.',
            'instruction': 'Monitor local forecasts.',
            'onset': '2026-04-04T14:00:00-07:00',
            'expires': '2026-04-05T20:00:00-07:00',
          }
        };

        final alert = WeatherAlert.fromJson(json);

        expect(alert.event, 'Flood Watch');
        expect(alert.severity, 'Moderate');
        expect(alert.headline, 'Flood Watch in effect until 8 PM PDT');
        expect(alert.description, 'Heavy rainfall expected.');
        expect(alert.instruction, 'Monitor local forecasts.');
        expect(alert.onset, DateTime.parse('2026-04-04T14:00:00-07:00'));
        expect(alert.expires, DateTime.parse('2026-04-05T20:00:00-07:00'));
      });

      test('falls back to effective when onset is null', () {
        final json = {
          'properties': {
            'event': 'Wind Advisory',
            'severity': 'Minor',
            'headline': 'Wind Advisory',
            'description': 'Gusty winds.',
            'instruction': null,
            'onset': null,
            'effective': '2026-04-04T10:00:00-07:00',
            'expires': '2026-04-04T18:00:00-07:00',
          }
        };

        final alert = WeatherAlert.fromJson(json);
        expect(alert.onset, DateTime.parse('2026-04-04T10:00:00-07:00'));
        expect(alert.instruction, '');
      });
    });

    group('WeatherAlert.alertColor', () {
      test('Extreme returns red', () {
        expect(WeatherAlert.alertColor('Extreme').value, 0xFFD32F2F);
      });
      test('Severe returns red', () {
        expect(WeatherAlert.alertColor('Severe').value, 0xFFD32F2F);
      });
      test('Moderate returns orange', () {
        expect(WeatherAlert.alertColor('Moderate').value, 0xFFF57C00);
      });
      test('Minor returns yellow', () {
        expect(WeatherAlert.alertColor('Minor').value, 0xFFF9A825);
      });
      test('Unknown returns orange', () {
        expect(WeatherAlert.alertColor('Unknown').value, 0xFFF57C00);
      });
    });

    group('WeatherAlert JSON round-trip', () {
      test('toJson → fromStoredJson preserves values', () {
        final original = WeatherAlert(
          event: 'Flood Watch',
          severity: 'Moderate',
          headline: 'Flood Watch',
          description: 'Heavy rain.',
          instruction: 'Be prepared.',
          onset: DateTime.utc(2026, 4, 4, 14),
          expires: DateTime.utc(2026, 4, 5, 20),
        );

        final restored = WeatherAlert.fromStoredJson(original.toJson());
        expect(restored.event, original.event);
        expect(restored.severity, original.severity);
        expect(restored.onset, original.onset);
      });
    });
  }
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  flutter test test/models/weather_alert_test.dart
  ```
  Expected: FAIL

- [ ] **Step 3: Implement WeatherAlert**

  ```dart
  // lib/models/weather_alert.dart
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
  ```

- [ ] **Step 4: Run tests — confirm pass**

  ```bash
  flutter test test/models/weather_alert_test.dart
  ```
  Expected: All PASS

- [ ] **Step 5: Commit**

  ```bash
  git add lib/models/weather_alert.dart test/models/weather_alert_test.dart
  git commit -m "feat: add WeatherAlert model with severity color helper"
  ```

---

## Task 5: Model — SavedLocation

**Files:**
- Create: `lib/models/saved_location.dart`
- Create: `test/models/saved_location_test.dart`

- [ ] **Step 1: Write the failing tests**

  ```dart
  // test/models/saved_location_test.dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:weather_gov/models/saved_location.dart';
  import 'package:weather_gov/models/hourly_period.dart';
  import 'package:weather_gov/models/weather_alert.dart';

  void main() {
    final samplePeriod = HourlyPeriod(
      startTime: DateTime.utc(2026, 4, 4, 21),
      temperature: 58,
      precipChance: 10,
      relativeHumidity: 17,
      dewpointF: 12.99,
      windSpeedMph: 3.0,
      windDirection: 'S',
      shortForecast: 'Partly Cloudy',
      iconUrl: 'https://example.com/icon.png',
    );

    final sampleAlert = WeatherAlert(
      event: 'Flood Watch',
      severity: 'Moderate',
      headline: 'Flood Watch',
      description: 'Heavy rain.',
      instruction: '',
      onset: DateTime.utc(2026, 4, 4, 14),
      expires: DateTime.utc(2026, 4, 5, 20),
    );

    group('SavedLocation JSON round-trip', () {
      test('toJson → fromJson preserves all fields', () {
        final location = SavedLocation(
          displayName: 'Bishop, CA',
          lat: 37.3636,
          lon: -118.394,
          lastAccessed: DateTime.utc(2026, 4, 4),
          cachedForecast: [samplePeriod],
          cachedAlerts: [sampleAlert],
          cacheTimestamp: DateTime.utc(2026, 4, 4, 12),
        );

        final restored = SavedLocation.fromJson(location.toJson());

        expect(restored.displayName, 'Bishop, CA');
        expect(restored.lat, 37.3636);
        expect(restored.lon, -118.394);
        expect(restored.cachedForecast.length, 1);
        expect(restored.cachedForecast.first.temperature, 58);
        expect(restored.cachedAlerts.length, 1);
        expect(restored.cachedAlerts.first.event, 'Flood Watch');
      });
    });
  }
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  flutter test test/models/saved_location_test.dart
  ```
  Expected: FAIL

- [ ] **Step 3: Implement SavedLocation**

  ```dart
  // lib/models/saved_location.dart
  import 'hourly_period.dart';
  import 'weather_alert.dart';

  class SavedLocation {
    final String displayName;
    final double lat;
    final double lon;
    final DateTime lastAccessed;
    final List<HourlyPeriod> cachedForecast;
    final List<WeatherAlert> cachedAlerts;
    final DateTime cacheTimestamp;

    const SavedLocation({
      required this.displayName,
      required this.lat,
      required this.lon,
      required this.lastAccessed,
      required this.cachedForecast,
      required this.cachedAlerts,
      required this.cacheTimestamp,
    });

    SavedLocation copyWith({
      String? displayName,
      double? lat,
      double? lon,
      DateTime? lastAccessed,
      List<HourlyPeriod>? cachedForecast,
      List<WeatherAlert>? cachedAlerts,
      DateTime? cacheTimestamp,
    }) {
      return SavedLocation(
        displayName: displayName ?? this.displayName,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        lastAccessed: lastAccessed ?? this.lastAccessed,
        cachedForecast: cachedForecast ?? this.cachedForecast,
        cachedAlerts: cachedAlerts ?? this.cachedAlerts,
        cacheTimestamp: cacheTimestamp ?? this.cacheTimestamp,
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
        };
  }
  ```

- [ ] **Step 4: Run tests — confirm pass**

  ```bash
  flutter test test/models/saved_location_test.dart
  ```
  Expected: All PASS

- [ ] **Step 5: Run all model tests together**

  ```bash
  flutter test test/models/
  ```
  Expected: All PASS

- [ ] **Step 6: Commit**

  ```bash
  git add lib/models/saved_location.dart test/models/saved_location_test.dart
  git commit -m "feat: add SavedLocation model with full JSON serialization"
  ```

---

## Task 6: NominatimService

**Files:**
- Create: `lib/services/nominatim_service.dart`
- Create: `test/services/nominatim_service_test.dart`

- [ ] **Step 1: Write the failing tests**

  ```dart
  // test/services/nominatim_service_test.dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:http/http.dart' as http;
  import 'package:http/testing.dart';
  import 'package:weather_gov/services/nominatim_service.dart';

  void main() {
    group('NominatimService.search', () {
      test('returns lat/lon and display name on success', () async {
        final client = MockClient((request) async {
          expect(request.url.host, 'nominatim.openstreetmap.org');
          expect(request.url.queryParameters['q'], 'Bishop, CA');
          expect(request.headers['User-Agent'], contains('WeatherGovApp'));
          return http.Response('''
            [{"display_name":"Bishop, Inyo County, California, United States",
              "lat":"37.3635",
              "lon":"-118.3949"}]
          ''', 200);
        });

        final service = NominatimService(client: client);
        final result = await service.search('Bishop, CA');

        expect(result, isNotNull);
        expect(result!.displayName, contains('Bishop'));
        expect(result.lat, closeTo(37.3635, 0.001));
        expect(result.lon, closeTo(-118.3949, 0.001));
      });

      test('returns null when no results found', () async {
        final client = MockClient((_) async => http.Response('[]', 200));
        final service = NominatimService(client: client);
        final result = await service.search('xyzxyzxyz');
        expect(result, isNull);
      });

      test('throws on HTTP error', () async {
        final client = MockClient((_) async => http.Response('error', 500));
        final service = NominatimService(client: client);
        expect(() => service.search('Bishop'), throwsException);
      });
    });
  }
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  flutter test test/services/nominatim_service_test.dart
  ```
  Expected: FAIL

- [ ] **Step 3: Implement NominatimService**

  ```dart
  // lib/services/nominatim_service.dart
  import 'dart:convert';
  import 'package:http/http.dart' as http;

  class GeocodingResult {
    final String displayName;
    final double lat;
    final double lon;

    const GeocodingResult({
      required this.displayName,
      required this.lat,
      required this.lon,
    });
  }

  class NominatimService {
    final http.Client _client;

    NominatimService({http.Client? client}) : _client = client ?? http.Client();

    Future<GeocodingResult?> search(String query) async {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
      });

      final response = await _client.get(uri, headers: {
        'User-Agent': 'WeatherGovApp/1.0',
        'Accept': 'application/json',
      });

      if (response.statusCode != 200) {
        throw Exception('Nominatim error: ${response.statusCode}');
      }

      final List<dynamic> results = json.decode(response.body) as List<dynamic>;
      if (results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      return GeocodingResult(
        displayName: first['display_name'] as String,
        lat: double.parse(first['lat'] as String),
        lon: double.parse(first['lon'] as String),
      );
    }
  }
  ```

- [ ] **Step 4: Run tests — confirm pass**

  ```bash
  flutter test test/services/nominatim_service_test.dart
  ```
  Expected: All PASS

- [ ] **Step 5: Commit**

  ```bash
  git add lib/services/nominatim_service.dart test/services/nominatim_service_test.dart
  git commit -m "feat: add NominatimService for city-to-coordinates geocoding"
  ```

---

## Task 7: NwsService

**Files:**
- Create: `lib/services/nws_service.dart`
- Create: `test/services/nws_service_test.dart`

- [ ] **Step 1: Write the failing tests**

  ```dart
  // test/services/nws_service_test.dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:http/http.dart' as http;
  import 'package:http/testing.dart';
  import 'package:weather_gov/services/nws_service.dart';

  const _pointsResponse = '''
  {
    "properties": {
      "gridId": "VEF",
      "gridX": 16,
      "gridY": 169,
      "forecastHourly": "https://api.weather.gov/gridpoints/VEF/16,169/forecast/hourly",
      "relativeLocation": {
        "properties": { "city": "Bishop", "state": "CA" }
      },
      "timeZone": "America/Los_Angeles"
    }
  }
  ''';

  const _hourlyResponse = '''
  {
    "properties": {
      "periods": [
        {
          "startTime": "2026-04-04T21:00:00-07:00",
          "temperature": 58,
          "probabilityOfPrecipitation": {"unitCode": "wmoUnit:percent", "value": 0},
          "relativeHumidity": {"unitCode": "wmoUnit:percent", "value": 17},
          "dewpoint": {"unitCode": "wmoUnit:degC", "value": -10.56},
          "windSpeed": "3 mph",
          "windDirection": "S",
          "shortForecast": "Partly Cloudy",
          "icon": "https://api.weather.gov/icons/land/night/few?size=small"
        }
      ]
    }
  }
  ''';

  const _alertsResponse = '''
  {
    "features": [
      {
        "properties": {
          "event": "Wind Advisory",
          "severity": "Minor",
          "headline": "Wind Advisory until 6 PM",
          "description": "Gusty winds.",
          "instruction": "Secure outdoor items.",
          "onset": "2026-04-04T09:00:00-07:00",
          "expires": "2026-04-04T18:00:00-07:00"
        }
      }
    ]
  }
  ''';

  void main() {
    group('NwsService.fetchForecast', () {
      test('returns location name, forecast periods, and alerts', () async {
        int callCount = 0;
        final client = MockClient((request) async {
          callCount++;
          if (request.url.path.contains('/points/')) {
            return http.Response(_pointsResponse, 200);
          }
          if (request.url.path.contains('/forecast/hourly')) {
            return http.Response(_hourlyResponse, 200);
          }
          if (request.url.path.contains('/alerts/active')) {
            return http.Response(_alertsResponse, 200);
          }
          return http.Response('not found', 404);
        });

        final service = NwsService(client: client);
        final result = await service.fetchForecast(37.3636, -118.394);

        expect(callCount, 3); // points + hourly + alerts
        expect(result.locationName, 'Bishop, CA');
        expect(result.periods.length, 1);
        expect(result.periods.first.temperature, 58);
        expect(result.alerts.length, 1);
        expect(result.alerts.first.event, 'Wind Advisory');
      });

      test('throws on points 404 (unsupported location)', () async {
        final client = MockClient((_) async => http.Response('{}', 404));
        final service = NwsService(client: client);
        expect(
          () => service.fetchForecast(0.0, 0.0),
          throwsA(isA<NwsUnsupportedLocationException>()),
        );
      });
    });
  }
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  flutter test test/services/nws_service_test.dart
  ```
  Expected: FAIL

- [ ] **Step 3: Implement NwsService**

  ```dart
  // lib/services/nws_service.dart
  import 'dart:convert';
  import 'package:http/http.dart' as http;
  import '../models/hourly_period.dart';
  import '../models/weather_alert.dart';

  class NwsForecastResult {
    final String locationName;
    final List<HourlyPeriod> periods;
    final List<WeatherAlert> alerts;

    const NwsForecastResult({
      required this.locationName,
      required this.periods,
      required this.alerts,
    });
  }

  class NwsUnsupportedLocationException implements Exception {
    final String message;
    const NwsUnsupportedLocationException(this.message);
    @override
    String toString() => message;
  }

  class NwsService {
    final http.Client _client;
    static const _base = 'https://api.weather.gov';
    static const _headers = {
      'User-Agent': 'WeatherGovApp/1.0',
      'Accept': 'application/geo+json',
    };

    NwsService({http.Client? client}) : _client = client ?? http.Client();

    Future<NwsForecastResult> fetchForecast(double lat, double lon) async {
      // Step 1: resolve grid point
      final pointsUri = Uri.parse('$_base/points/${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}');
      final pointsResp = await _client.get(pointsUri, headers: _headers);

      if (pointsResp.statusCode == 404) {
        throw const NwsUnsupportedLocationException(
            'Location not supported by NWS');
      }
      if (pointsResp.statusCode != 200) {
        throw Exception('NWS points error: ${pointsResp.statusCode}');
      }

      final pointsJson = json.decode(pointsResp.body) as Map<String, dynamic>;
      final props = pointsJson['properties'] as Map<String, dynamic>;
      final hourlyUrl = props['forecastHourly'] as String;
      final relLoc = (props['relativeLocation'] as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      final locationName = '${relLoc['city']}, ${relLoc['state']}';

      // Steps 2 & 3 fire in parallel
      final alertsUri = Uri.parse('$_base/alerts/active?point=$lat,$lon');
      final results = await Future.wait([
        _client.get(Uri.parse(hourlyUrl), headers: _headers),
        _client.get(alertsUri, headers: _headers),
      ]);

      final hourlyResp = results[0];
      final alertsResp = results[1];

      if (hourlyResp.statusCode != 200) {
        throw Exception('NWS hourly error: ${hourlyResp.statusCode}');
      }

      final hourlyJson = json.decode(hourlyResp.body) as Map<String, dynamic>;
      final periodsJson = (hourlyJson['properties']['periods'] as List<dynamic>);
      final periods = periodsJson
          .map((e) => HourlyPeriod.fromJson(e as Map<String, dynamic>))
          .toList();

      // Alerts are non-critical — suppress errors
      List<WeatherAlert> alerts = [];
      if (alertsResp.statusCode == 200) {
        final alertsJson = json.decode(alertsResp.body) as Map<String, dynamic>;
        alerts = (alertsJson['features'] as List<dynamic>)
            .map((e) => WeatherAlert.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      return NwsForecastResult(
        locationName: locationName,
        periods: periods,
        alerts: alerts,
      );
    }
  }
  ```

- [ ] **Step 4: Run tests — confirm pass**

  ```bash
  flutter test test/services/nws_service_test.dart
  ```
  Expected: All PASS

- [ ] **Step 5: Commit**

  ```bash
  git add lib/services/nws_service.dart test/services/nws_service_test.dart
  git commit -m "feat: add NwsService for NWS API forecast and alerts fetching"
  ```

---

## Task 8: CacheService

**Files:**
- Create: `lib/services/cache_service.dart`
- Create: `test/services/cache_service_test.dart`

- [ ] **Step 1: Write the failing tests**

  ```dart
  // test/services/cache_service_test.dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:weather_gov/services/cache_service.dart';
  import 'package:weather_gov/models/saved_location.dart';

  SavedLocation _makeLocation(String name, DateTime lastAccessed) {
    return SavedLocation(
      displayName: name,
      lat: 37.0,
      lon: -118.0,
      lastAccessed: lastAccessed,
      cachedForecast: [],
      cachedAlerts: [],
      cacheTimestamp: DateTime.utc(2026, 1, 1),
    );
  }

  void main() {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('CacheService', () {
      test('loads empty list when nothing cached', () async {
        final prefs = await SharedPreferences.getInstance();
        final cache = CacheService(prefs);
        expect(cache.loadAll(), isEmpty);
      });

      test('saves and reloads locations', () async {
        final prefs = await SharedPreferences.getInstance();
        final cache = CacheService(prefs);
        final loc = _makeLocation('Bishop, CA', DateTime.utc(2026, 4, 4));
        cache.saveAll([loc]);

        final prefs2 = await SharedPreferences.getInstance();
        final cache2 = CacheService(prefs2);
        final loaded = cache2.loadAll();

        expect(loaded.length, 1);
        expect(loaded.first.displayName, 'Bishop, CA');
      });

      test('evicts oldest by lastAccessed when 11th location added', () async {
        final prefs = await SharedPreferences.getInstance();
        final cache = CacheService(prefs);

        final locations = List.generate(10, (i) =>
          _makeLocation('City $i', DateTime.utc(2026, 1, i + 1)));
        cache.saveAll(locations);

        final newLoc = _makeLocation('New City', DateTime.utc(2026, 2, 1));
        final updated = cache.addOrUpdate(cache.loadAll(), newLoc);

        expect(updated.length, 10);
        expect(updated.any((l) => l.displayName == 'City 0'), isFalse);
        expect(updated.any((l) => l.displayName == 'New City'), isTrue);
      });

      test('updating existing location replaces it and refreshes lastAccessed', () async {
        final prefs = await SharedPreferences.getInstance();
        final cache = CacheService(prefs);

        final loc = _makeLocation('Bishop, CA', DateTime.utc(2026, 1, 1));
        cache.saveAll([loc]);

        final updated = _makeLocation('Bishop, CA', DateTime.utc(2026, 4, 4));
        final result = cache.addOrUpdate(cache.loadAll(), updated);

        expect(result.length, 1);
        expect(result.first.lastAccessed, DateTime.utc(2026, 4, 4));
      });
    });
  }
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  flutter test test/services/cache_service_test.dart
  ```
  Expected: FAIL

- [ ] **Step 3: Implement CacheService**

  ```dart
  // lib/services/cache_service.dart
  import 'dart:convert';
  import 'package:shared_preferences/shared_preferences.dart';
  import '../models/saved_location.dart';
  import '../constants.dart';

  class CacheService {
    static const _key = 'saved_locations';
    final SharedPreferences _prefs;

    CacheService(this._prefs);

    List<SavedLocation> loadAll() {
      final raw = _prefs.getString(_key);
      if (raw == null) return [];
      final list = json.decode(raw) as List<dynamic>;
      return list
          .map((e) => SavedLocation.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    void saveAll(List<SavedLocation> locations) {
      final encoded = json.encode(locations.map((l) => l.toJson()).toList());
      _prefs.setString(_key, encoded);
    }

    /// Adds or replaces a location, then evicts the oldest if over the limit.
    /// Returns the updated list (does not save — caller must call saveAll).
    List<SavedLocation> addOrUpdate(
        List<SavedLocation> existing, SavedLocation incoming) {
      final updated = existing
          .where((l) => l.displayName != incoming.displayName)
          .toList();
      updated.add(incoming);

      if (updated.length > kMaxSavedLocations) {
        updated.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
        updated.removeAt(0); // remove oldest
      }

      return updated;
    }
  }
  ```

- [ ] **Step 4: Run tests — confirm pass**

  ```bash
  flutter test test/services/cache_service_test.dart
  ```
  Expected: All PASS

- [ ] **Step 5: Commit**

  ```bash
  git add lib/services/cache_service.dart test/services/cache_service_test.dart
  git commit -m "feat: add CacheService with 10-location LRU eviction"
  ```

---

## Task 9: ForecastProvider

**Files:**
- Create: `lib/providers/forecast_provider.dart`
- Create: `test/providers/forecast_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

  ```dart
  // test/providers/forecast_provider_test.dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:weather_gov/providers/forecast_provider.dart';
  import 'package:weather_gov/services/nominatim_service.dart';
  import 'package:weather_gov/services/nws_service.dart';
  import 'package:weather_gov/services/cache_service.dart';
  import 'package:weather_gov/models/hourly_period.dart';
  import 'package:weather_gov/models/weather_alert.dart';
  import 'package:weather_gov/models/saved_location.dart';
  import 'package:weather_gov/constants.dart';
  import 'package:http/http.dart' as http;
  import 'package:http/testing.dart';

  // Minimal fake HTTP client that returns valid data for all NWS endpoints
  http.Client _makeNwsClient() {
    return MockClient((request) async {
      if (request.url.path.contains('/points/')) {
        return http.Response('''
          {"properties":{"gridId":"VEF","gridX":16,"gridY":169,
           "forecastHourly":"https://api.weather.gov/gridpoints/VEF/16,169/forecast/hourly",
           "relativeLocation":{"properties":{"city":"Bishop","state":"CA"}},
           "timeZone":"America/Los_Angeles"}}
        ''', 200);
      }
      if (request.url.path.contains('/forecast/hourly')) {
        return http.Response('''
          {"properties":{"periods":[
            {"startTime":"2026-04-04T21:00:00-07:00","temperature":58,
             "probabilityOfPrecipitation":{"unitCode":"wmoUnit:percent","value":0},
             "relativeHumidity":{"unitCode":"wmoUnit:percent","value":17},
             "dewpoint":{"unitCode":"wmoUnit:degC","value":-10.56},
             "windSpeed":"3 mph","windDirection":"S",
             "shortForecast":"Partly Cloudy",
             "icon":"https://api.weather.gov/icons/land/night/few?size=small"}
          ]}}
        ''', 200);
      }
      return http.Response('{"features":[]}', 200); // alerts
    });
  }

  http.Client _makeNominatimClient() {
    return MockClient((_) async => http.Response('''
      [{"display_name":"Bishop, Inyo County, California, United States",
        "lat":"37.3636","lon":"-118.394"}]
    ''', 200));
  }

  Future<ForecastProvider> _makeProvider() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ForecastProvider(
      nwsService: NwsService(client: _makeNwsClient()),
      nominatimService: NominatimService(client: _makeNominatimClient()),
      cacheService: CacheService(prefs),
    );
  }

  void main() {
    group('ForecastProvider initial state', () {
      test('starts with no location and default row visibility', () async {
        final provider = await _makeProvider();
        expect(provider.currentLocation, isNull);
        expect(provider.visibleRows[kRowTemperature], isTrue);
        expect(provider.visibleRows[kRowDewpoint], isFalse);
        expect(provider.isLoading, isFalse);
      });
    });

    group('ForecastProvider.searchLocation', () {
      test('sets currentLocation and saves to cache', () async {
        final provider = await _makeProvider();
        await provider.searchLocation('Bishop, CA');

        expect(provider.currentLocation, isNotNull);
        expect(provider.currentLocation!.displayName, contains('Bishop'));
        expect(provider.currentLocation!.cachedForecast.length, 1);
        expect(provider.savedLocations.length, 1);
        expect(provider.isLoading, isFalse);
      });

      test('sets errorMessage on location not found', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final provider = ForecastProvider(
          nwsService: NwsService(client: _makeNwsClient()),
          nominatimService: NominatimService(
            client: MockClient((_) async => http.Response('[]', 200)),
          ),
          cacheService: CacheService(prefs),
        );

        await provider.searchLocation('xyzxyz');
        expect(provider.errorMessage, contains('not found'));
        expect(provider.currentLocation, isNull);
      });
    });

    group('ForecastProvider.toggleRow', () {
      test('flips row visibility', () async {
        final provider = await _makeProvider();
        expect(provider.visibleRows[kRowTemperature], isTrue);
        provider.toggleRow(kRowTemperature);
        expect(provider.visibleRows[kRowTemperature], isFalse);
        provider.toggleRow(kRowTemperature);
        expect(provider.visibleRows[kRowTemperature], isTrue);
      });
    });

    group('ForecastProvider.toggleDarkMode', () {
      test('flips isDarkMode', () async {
        final provider = await _makeProvider();
        expect(provider.isDarkMode, isFalse);
        provider.toggleDarkMode();
        expect(provider.isDarkMode, isTrue);
      });
    });

    group('ForecastProvider.selectLocation', () {
      test('loads cached location as current', () async {
        final provider = await _makeProvider();
        await provider.searchLocation('Bishop, CA');

        final saved = provider.savedLocations.first;
        provider.selectLocation(saved);

        expect(provider.currentLocation!.displayName, saved.displayName);
      });
    });
  }
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  flutter test test/providers/forecast_provider_test.dart
  ```
  Expected: FAIL

- [ ] **Step 3: Implement ForecastProvider**

  ```dart
  // lib/providers/forecast_provider.dart
  import 'package:flutter/foundation.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import '../constants.dart';
  import '../models/saved_location.dart';
  import '../models/weather_alert.dart';
  import '../services/nominatim_service.dart';
  import '../services/nws_service.dart';
  import '../services/cache_service.dart';

  class ForecastProvider extends ChangeNotifier {
    final NwsService _nwsService;
    final NominatimService _nominatimService;
    final CacheService _cacheService;
    final SharedPreferences? _prefs;

    SavedLocation? currentLocation;
    List<SavedLocation> savedLocations = [];
    Map<String, bool> visibleRows = Map.from(kDefaultRowVisibility);
    bool isDarkMode = false;
    bool isLoading = false;
    String? errorMessage;

    ForecastProvider({
      required NwsService nwsService,
      required NominatimService nominatimService,
      required CacheService cacheService,
      SharedPreferences? prefs,
    })  : _nwsService = nwsService,
          _nominatimService = nominatimService,
          _cacheService = cacheService,
          _prefs = prefs;

    /// Call once at startup to restore cached state and preferences.
    Future<void> init() async {
      savedLocations = _cacheService.loadAll();
      if (savedLocations.isNotEmpty) {
        savedLocations.sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
        currentLocation = savedLocations.first;
      }
      _loadPreferences();
      notifyListeners();
    }

    void _loadPreferences() {
      if (_prefs == null) return;
      isDarkMode = _prefs!.getBool('isDarkMode') ?? false;
      for (final row in kAllRows) {
        final saved = _prefs!.getBool('row_$row');
        if (saved != null) visibleRows[row] = saved;
      }
    }

    void _savePreferences() {
      if (_prefs == null) return;
      _prefs!.setBool('isDarkMode', isDarkMode);
      for (final entry in visibleRows.entries) {
        _prefs!.setBool('row_${entry.key}', entry.value);
      }
    }

    Future<void> searchLocation(String query) async {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      try {
        final geo = await _nominatimService.search(query);
        if (geo == null) {
          errorMessage = 'Location not found';
          return;
        }
        await _fetchAndSave(geo.displayName, geo.lat, geo.lon);
      } catch (e) {
        errorMessage = 'Error: $e';
      } finally {
        isLoading = false;
        notifyListeners();
      }
    }

    Future<void> refreshCurrentLocation() async {
      if (currentLocation == null) return;
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      try {
        await _fetchAndSave(
          currentLocation!.displayName,
          currentLocation!.lat,
          currentLocation!.lon,
        );
      } on NwsUnsupportedLocationException catch (e) {
        errorMessage = e.toString();
      } catch (e) {
        errorMessage = 'Forecast unavailable, showing cached data';
      } finally {
        isLoading = false;
        notifyListeners();
      }
    }

    Future<void> _fetchAndSave(
        String displayName, double lat, double lon) async {
      final result = await _nwsService.fetchForecast(lat, lon);
      final now = DateTime.now();
      final location = SavedLocation(
        displayName: result.locationName,
        lat: lat,
        lon: lon,
        lastAccessed: now,
        cachedForecast: result.periods,
        cachedAlerts: result.alerts,
        cacheTimestamp: now,
      );

      savedLocations = _cacheService.addOrUpdate(savedLocations, location);
      _cacheService.saveAll(savedLocations);
      currentLocation = location;
    }

    void selectLocation(SavedLocation location) {
      currentLocation = location.copyWith(lastAccessed: DateTime.now());
      savedLocations = _cacheService.addOrUpdate(savedLocations, currentLocation!);
      _cacheService.saveAll(savedLocations);
      notifyListeners();
    }

    void toggleRow(String rowName) {
      visibleRows[rowName] = !(visibleRows[rowName] ?? true);
      _savePreferences();
      notifyListeners();
    }

    void toggleDarkMode() {
      isDarkMode = !isDarkMode;
      _savePreferences();
      notifyListeners();
    }
  }
  ```

- [ ] **Step 4: Run tests — confirm pass**

  ```bash
  flutter test test/providers/forecast_provider_test.dart
  ```
  Expected: All PASS

- [ ] **Step 5: Run full test suite**

  ```bash
  flutter test
  ```
  Expected: All PASS

- [ ] **Step 6: Commit**

  ```bash
  git add lib/providers/forecast_provider.dart test/providers/forecast_provider_test.dart
  git commit -m "feat: add ForecastProvider with search, cache, toggles, and dark mode"
  ```

---

## Task 10: App Entry Point & Theme

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace main.dart with full app wiring**

  ```dart
  // lib/main.dart
  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:http/http.dart' as http;
  import 'providers/forecast_provider.dart';
  import 'services/nws_service.dart';
  import 'services/nominatim_service.dart';
  import 'services/cache_service.dart';
  import 'ui/chart_screen.dart';

  void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final client = http.Client();

    final provider = ForecastProvider(
      nwsService: NwsService(client: client),
      nominatimService: NominatimService(client: client),
      cacheService: CacheService(prefs),
      prefs: prefs,
    );
    await provider.init();

    runApp(
      ChangeNotifierProvider.value(
        value: provider,
        child: const WeatherApp(),
      ),
    );
  }

  class WeatherApp extends StatelessWidget {
    const WeatherApp({super.key});

    @override
    Widget build(BuildContext context) {
      final isDark = context.select<ForecastProvider, bool>((p) => p.isDarkMode);
      return MaterialApp(
        title: 'Weather Forecast',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const ChartScreen(),
      );
    }
  }
  ```

- [ ] **Step 2: Create a stub ChartScreen so the app compiles**

  ```dart
  // lib/ui/chart_screen.dart
  import 'package:flutter/material.dart';

  class ChartScreen extends StatelessWidget {
    const ChartScreen({super.key});

    @override
    Widget build(BuildContext context) {
      return const Scaffold(
        body: Center(child: Text('Chart coming soon')),
      );
    }
  }
  ```

- [ ] **Step 3: Build and verify it compiles**

  ```bash
  flutter build apk --debug
  ```
  Expected: Build succeeds

- [ ] **Step 4: Commit**

  ```bash
  git add lib/main.dart lib/ui/chart_screen.dart
  git commit -m "feat: wire app entry point with provider, theme, and Material 3"
  ```

---

## Task 11: AlertBanner & AlertDetailSheet

**Files:**
- Create: `lib/ui/alert_banner.dart`
- Create: `lib/ui/alert_detail_sheet.dart`

- [ ] **Step 1: Create AlertDetailSheet**

  ```dart
  // lib/ui/alert_detail_sheet.dart
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
                  Container(width: 12, height: 12,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(alert.event,
                    style: Theme.of(context).textTheme.titleMedium
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
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ],
            );
          },
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Create AlertBanner**

  ```dart
  // lib/ui/alert_banner.dart
  import 'package:flutter/material.dart';
  import '../models/weather_alert.dart';
  import 'alert_detail_sheet.dart';

  class AlertBanner extends StatelessWidget {
    final List<WeatherAlert> alerts;

    const AlertBanner({super.key, required this.alerts});

    @override
    Widget build(BuildContext context) {
      if (alerts.isEmpty) return const SizedBox.shrink();

      // Use the highest severity color among all alerts
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
                style: const TextStyle(color: Colors.white, fontSize: 13,
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
  ```

- [ ] **Step 3: Build to verify no compile errors**

  ```bash
  flutter build apk --debug
  ```
  Expected: Build succeeds

- [ ] **Step 4: Commit**

  ```bash
  git add lib/ui/alert_banner.dart lib/ui/alert_detail_sheet.dart
  git commit -m "feat: add AlertBanner and AlertDetailSheet with severity color-coding"
  ```

---

## Task 12: Time Axis Widget

**Files:**
- Create: `lib/ui/time_axis.dart`

- [ ] **Step 1: Create TimeAxis**

  ```dart
  // lib/ui/time_axis.dart
  import 'package:flutter/material.dart';
  import 'package:intl/intl.dart';
  import '../constants.dart';
  import '../models/hourly_period.dart';

  class TimeAxis extends StatelessWidget {
    final List<HourlyPeriod> periods;

    const TimeAxis({super.key, required this.periods});

    @override
    Widget build(BuildContext context) {
      final textTheme = Theme.of(context).textTheme;
      return SizedBox(
        height: kTimeAxisHeight,
        child: Row(
          children: periods.asMap().entries.map((entry) {
            final i = entry.key;
            final period = entry.value;
            final hour = period.startTime.toLocal().hour;
            final isFirstOrMidnight = i == 0 || hour == 0;
            final showSixHour = hour % 6 == 0;

            String? label;
            TextStyle? style;
            if (isFirstOrMidnight) {
              label = DateFormat('EEE').format(period.startTime.toLocal());
              style = textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold);
            } else if (showSixHour) {
              label = hour < 12
                  ? '${hour}am'
                  : hour == 12
                      ? '12pm'
                      : '${hour - 12}pm';
              style = textTheme.labelSmall;
            }

            return SizedBox(
              width: kPixelsPerHour,
              child: label != null
                  ? Text(label,
                      style: style,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                      softWrap: false)
                  : null,
            );
          }).toList(),
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add lib/ui/time_axis.dart
  git commit -m "feat: add TimeAxis widget with day and hour labels"
  ```

---

## Task 13: Chart Row Widgets

**Files:**
- Create: `lib/ui/chart_rows/line_chart_row.dart`
- Create: `lib/ui/chart_rows/bar_chart_row.dart`
- Create: `lib/ui/chart_rows/area_chart_row.dart`
- Create: `lib/ui/chart_rows/wind_direction_row.dart`
- Create: `lib/ui/chart_rows/conditions_row.dart`

- [ ] **Step 1: Create LineChartRow (Temperature & Dewpoint)**

  ```dart
  // lib/ui/chart_rows/line_chart_row.dart
  import 'package:flutter/material.dart';
  import 'package:fl_chart/fl_chart.dart';
  import '../../constants.dart';
  import '../../models/hourly_period.dart';

  class LineChartRow extends StatelessWidget {
    final List<HourlyPeriod> periods;
    final Color color;
    final List<double> Function(HourlyPeriod) valueSelector;

    const LineChartRow({
      super.key,
      required this.periods,
      required this.color,
      required this.valueSelector,
    });

    @override
    Widget build(BuildContext context) {
      final values = periods.map((p) => valueSelector(p).first).toList();
      final minVal = values.reduce((a, b) => a < b ? a : b) - 5;
      final maxVal = values.reduce((a, b) => a > b ? a : b) + 5;

      final spots = periods.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), valueSelector(e.value).first)).toList();

      return SizedBox(
        width: periods.length * kPixelsPerHour,
        height: kChartRowHeight,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (periods.length - 1).toDouble(),
            minY: minVal,
            maxY: maxVal,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: color,
                isCurved: true,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            ],
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Create BarChartRow (Precip Chance & Wind Speed)**

  ```dart
  // lib/ui/chart_rows/bar_chart_row.dart
  import 'package:flutter/material.dart';
  import 'package:fl_chart/fl_chart.dart';
  import '../../constants.dart';
  import '../../models/hourly_period.dart';

  class BarChartRow extends StatelessWidget {
    final List<HourlyPeriod> periods;
    final Color color;
    final double Function(HourlyPeriod) valueSelector;
    final double maxY;

    const BarChartRow({
      super.key,
      required this.periods,
      required this.color,
      required this.valueSelector,
      this.maxY = 100,
    });

    @override
    Widget build(BuildContext context) {
      return SizedBox(
        width: periods.length * kPixelsPerHour,
        height: kChartRowHeight,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            barGroups: periods.asMap().entries.map((e) =>
              BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: valueSelector(e.value),
                    color: color,
                    width: kPixelsPerHour * 0.75,
                    borderRadius: BorderRadius.zero,
                  ),
                ],
              )).toList(),
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 3: Create AreaChartRow (Humidity)**

  ```dart
  // lib/ui/chart_rows/area_chart_row.dart
  import 'package:flutter/material.dart';
  import 'package:fl_chart/fl_chart.dart';
  import '../../constants.dart';
  import '../../models/hourly_period.dart';

  class AreaChartRow extends StatelessWidget {
    final List<HourlyPeriod> periods;
    final Color color;
    final double Function(HourlyPeriod) valueSelector;

    const AreaChartRow({
      super.key,
      required this.periods,
      required this.color,
      required this.valueSelector,
    });

    @override
    Widget build(BuildContext context) {
      final spots = periods.asMap().entries
          .map((e) => FlSpot(e.key.toDouble(), valueSelector(e.value)))
          .toList();

      return SizedBox(
        width: periods.length * kPixelsPerHour,
        height: kChartRowHeight,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (periods.length - 1).toDouble(),
            minY: 0,
            maxY: 100,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: color,
                isCurved: true,
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withOpacity(0.3),
                ),
              ),
            ],
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 4: Create WindDirectionRow**

  ```dart
  // lib/ui/chart_rows/wind_direction_row.dart
  import 'dart:math';
  import 'package:flutter/material.dart';
  import '../../constants.dart';
  import '../../models/hourly_period.dart';

  const _cardinalDegrees = <String, double>{
    'N': 0, 'NNE': 22.5, 'NE': 45, 'ENE': 67.5,
    'E': 90, 'ESE': 112.5, 'SE': 135, 'SSE': 157.5,
    'S': 180, 'SSW': 202.5, 'SW': 225, 'WSW': 247.5,
    'W': 270, 'WNW': 292.5, 'NW': 315, 'NNW': 337.5,
  };

  class WindDirectionRow extends StatelessWidget {
    final List<HourlyPeriod> periods;

    const WindDirectionRow({super.key, required this.periods});

    @override
    Widget build(BuildContext context) {
      return SizedBox(
        width: periods.length * kPixelsPerHour,
        height: kChartRowHeight,
        child: Row(
          children: periods.map((p) {
            final degrees = _cardinalDegrees[p.windDirection] ?? 0.0;
            final radians = degrees * pi / 180;
            return SizedBox(
              width: kPixelsPerHour,
              height: kChartRowHeight,
              child: Center(
                child: Transform.rotate(
                  angle: radians,
                  child: Icon(
                    Icons.arrow_upward,
                    size: kPixelsPerHour * 0.75,
                    color: kColorWindDirection,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }
  }
  ```

- [ ] **Step 5: Create ConditionsRow**

  ```dart
  // lib/ui/chart_rows/conditions_row.dart
  import 'package:flutter/material.dart';
  import '../../constants.dart';
  import '../../models/hourly_period.dart';

  class ConditionsRow extends StatelessWidget {
    final List<HourlyPeriod> periods;

    const ConditionsRow({super.key, required this.periods});

    @override
    Widget build(BuildContext context) {
      return SizedBox(
        width: periods.length * kPixelsPerHour,
        height: kChartRowHeight,
        child: Row(
          children: periods.map((p) => SizedBox(
            width: kPixelsPerHour,
            height: kChartRowHeight,
            child: p.iconUrl.isNotEmpty
                ? Image.network(
                    p.iconUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.cloud, size: 16),
                  )
                : const Icon(Icons.cloud, size: 16),
          )).toList(),
        ),
      );
    }
  }
  ```

- [ ] **Step 6: Build to verify no compile errors**

  ```bash
  flutter build apk --debug
  ```
  Expected: Build succeeds

- [ ] **Step 7: Commit**

  ```bash
  git add lib/ui/chart_rows/ lib/ui/time_axis.dart
  git commit -m "feat: add all chart row widgets (line, bar, area, wind direction, conditions)"
  ```

---

## Task 14: ScrollableChart

**Files:**
- Create: `lib/ui/scrollable_chart.dart`

- [ ] **Step 1: Create ScrollableChart**

  ```dart
  // lib/ui/scrollable_chart.dart
  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
  import '../constants.dart';
  import '../models/hourly_period.dart';
  import '../providers/forecast_provider.dart';
  import 'time_axis.dart';
  import 'chart_rows/line_chart_row.dart';
  import 'chart_rows/bar_chart_row.dart';
  import 'chart_rows/area_chart_row.dart';
  import 'chart_rows/wind_direction_row.dart';
  import 'chart_rows/conditions_row.dart';

  class ScrollableChart extends StatelessWidget {
    final List<HourlyPeriod> periods;

    const ScrollableChart({super.key, required this.periods});

    @override
    Widget build(BuildContext context) {
      final provider = context.watch<ForecastProvider>();
      final visible = provider.visibleRows;
      final textTheme = Theme.of(context).textTheme;

      final rows = _buildRows(periods, visible);
      if (rows.isEmpty) {
        return const Center(child: Text('All rows hidden. Enable some in the menu.'));
      }

      final labels = _buildLabels(visible);

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned label column
          SizedBox(
            width: kLabelColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(height: kTimeAxisHeight), // align with time axis
                ...labels.map((label) => SizedBox(
                  height: kChartRowHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: Text(label,
                        style: textTheme.labelSmall,
                        textAlign: TextAlign.right),
                    ),
                  ),
                )),
              ],
            ),
          ),
          // Scrollable chart area
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TimeAxis(periods: periods),
                  ...rows,
                ],
              ),
            ),
          ),
        ],
      );
    }

    List<String> _buildLabels(Map<String, bool> visible) {
      return kAllRows.where((r) => visible[r] == true).toList();
    }

    List<Widget> _buildRows(
        List<HourlyPeriod> periods, Map<String, bool> visible) {
      final widgets = <Widget>[];

      void addIf(String key, Widget widget) {
        if (visible[key] == true) widgets.add(widget);
      }

      addIf(kRowTemperature, LineChartRow(
        periods: periods,
        color: kColorTemperature,
        valueSelector: (p) => [p.temperature.toDouble()],
      ));
      addIf(kRowDewpoint, LineChartRow(
        periods: periods,
        color: kColorDewpoint,
        valueSelector: (p) => [p.dewpointF],
      ));
      addIf(kRowPrecip, BarChartRow(
        periods: periods,
        color: kColorPrecip,
        valueSelector: (p) => p.precipChance.toDouble(),
        maxY: 100,
      ));
      addIf(kRowHumidity, AreaChartRow(
        periods: periods,
        color: kColorHumidity,
        valueSelector: (p) => p.relativeHumidity.toDouble(),
      ));

      final maxWind = periods.isEmpty
          ? 50.0
          : periods.map((p) => p.windSpeedMph).reduce((a, b) => a > b ? a : b) + 5;
      addIf(kRowWindSpeed, BarChartRow(
        periods: periods,
        color: kColorWindSpeed,
        valueSelector: (p) => p.windSpeedMph,
        maxY: maxWind,
      ));
      addIf(kRowWindDirection, WindDirectionRow(periods: periods));
      addIf(kRowConditions, ConditionsRow(periods: periods));

      return widgets;
    }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add lib/ui/scrollable_chart.dart
  git commit -m "feat: add ScrollableChart with pinned labels and shared scroll"
  ```

---

## Task 15: AppDrawer

**Files:**
- Create: `lib/ui/app_drawer.dart`

- [ ] **Step 1: Create AppDrawer**

  ```dart
  // lib/ui/app_drawer.dart
  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
  import '../constants.dart';
  import '../providers/forecast_provider.dart';

  class AppDrawer extends StatefulWidget {
    const AppDrawer({super.key});

    @override
    State<AppDrawer> createState() => _AppDrawerState();
  }

  class _AppDrawerState extends State<AppDrawer> {
    final _searchController = TextEditingController();

    @override
    void dispose() {
      _searchController.dispose();
      super.dispose();
    }

    void _onSearch(BuildContext context, ForecastProvider provider) {
      final query = _searchController.text.trim();
      if (query.isEmpty) return;
      Navigator.pop(context); // close drawer
      provider.searchLocation(query);
      _searchController.clear();
    }

    @override
    Widget build(BuildContext context) {
      final provider = context.watch<ForecastProvider>();

      return Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search location...',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => _onSearch(context, provider),
                    ),
                  ),
                  onSubmitted: (_) => _onSearch(context, provider),
                  textInputAction: TextInputAction.search,
                ),
              ),

              // Past Locations dropdown
              if (provider.savedLocations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Past Locations',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    value: provider.currentLocation?.displayName,
                    items: provider.savedLocations
                        .map((loc) => DropdownMenuItem(
                              value: loc.displayName,
                              child: Text(loc.displayName,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (name) {
                      if (name == null) return;
                      final loc = provider.savedLocations
                          .firstWhere((l) => l.displayName == name);
                      Navigator.pop(context);
                      provider.selectLocation(loc);
                    },
                  ),
                ),

              // Grab new data button
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: FilledButton.tonal(
                  onPressed: provider.isLoading || provider.currentLocation == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          provider.refreshCurrentLocation();
                        },
                  child: provider.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Grab new data'),
                ),
              ),

              const Divider(height: 24),

              // Row toggles
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: kAllRows.map((row) {
                    return SwitchListTile(
                      title: Text(row,
                          style: Theme.of(context).textTheme.bodyMedium),
                      value: provider.visibleRows[row] ?? true,
                      onChanged: (_) => provider.toggleRow(row),
                      dense: true,
                    );
                  }).toList(),
                ),
              ),

              const Divider(height: 1),

              // Dark mode toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SwitchListTile(
                  title: Text(
                    provider.isDarkMode ? '\u263e Dark Mode' : '\u2600 Dark Mode',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  value: provider.isDarkMode,
                  onChanged: (_) => provider.toggleDarkMode(),
                  dense: true,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add lib/ui/app_drawer.dart
  git commit -m "feat: add AppDrawer with search, past locations, row toggles, and dark mode"
  ```

---

## Task 16: ChartScreen — Wire Everything Together

**Files:**
- Modify: `lib/ui/chart_screen.dart`

- [ ] **Step 1: Replace stub ChartScreen with full implementation**

  ```dart
  // lib/ui/chart_screen.dart
  import 'package:flutter/material.dart';
  import 'package:provider/provider.dart';
  import 'package:intl/intl.dart';
  import '../providers/forecast_provider.dart';
  import 'app_drawer.dart';
  import 'alert_banner.dart';
  import 'scrollable_chart.dart';

  class ChartScreen extends StatelessWidget {
    const ChartScreen({super.key});

    @override
    Widget build(BuildContext context) {
      final provider = context.watch<ForecastProvider>();
      final location = provider.currentLocation;

      return Scaffold(
        appBar: AppBar(
          title: Text(location?.displayName ?? 'Weather Forecast'),
          centerTitle: false,
        ),
        drawer: const AppDrawer(),
        body: Column(
          children: [
            // Alert banner sits directly below the app bar
            if (location != null)
              AlertBanner(alerts: location.cachedAlerts),

            // Offline / cache timestamp banner
            if (location != null)
              _CacheBanner(location: location),

            // Error message
            if (provider.errorMessage != null)
              _ErrorBanner(message: provider.errorMessage!),

            // Loading indicator
            if (provider.isLoading)
              const LinearProgressIndicator(),

            // Main chart or empty state
            Expanded(
              child: location == null
                  ? const _EmptyState()
                  : location.cachedForecast.isEmpty
                      ? const Center(child: Text('No forecast data available.'))
                      : ScrollableChart(periods: location.cachedForecast),
            ),
          ],
        ),
      );
    }
  }

  class _CacheBanner extends StatelessWidget {
    final dynamic location; // SavedLocation

    const _CacheBanner({required this.location});

    @override
    Widget build(BuildContext context) {
      final fmt = DateFormat('EEE, MMM d h:mm a');
      final timestamp = fmt.format(location.cacheTimestamp.toLocal());
      return Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          'Showing cached data from $timestamp',
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
      );
    }
  }

  class _ErrorBanner extends StatelessWidget {
    final String message;
    const _ErrorBanner({required this.message});

    @override
    Widget build(BuildContext context) {
      return MaterialBanner(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () =>
                context.read<ForecastProvider>().refreshCurrentLocation(),
            child: const Text('Retry'),
          ),
        ],
        backgroundColor:
            Theme.of(context).colorScheme.errorContainer,
      );
    }
  }

  class _EmptyState extends StatelessWidget {
    const _EmptyState();

    @override
    Widget build(BuildContext context) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_sunny_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Open the menu to search for a location',
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Build debug APK and verify no errors**

  ```bash
  flutter build apk --debug
  ```
  Expected: Build succeeds

- [ ] **Step 3: Run all tests**

  ```bash
  flutter test
  ```
  Expected: All PASS

- [ ] **Step 4: Commit**

  ```bash
  git add lib/ui/chart_screen.dart
  git commit -m "feat: wire ChartScreen with AppBar, AlertBanner, ScrollableChart, and empty state"
  ```

---

## Task 17: Build Release APK & Sideload

**Files:**
- No code changes

- [ ] **Step 1: Build release APK**

  ```bash
  flutter build apk --release
  ```
  Expected output:
  ```
  Built build/app/outputs/flutter-apk/app-release.apk (XX.XMB)
  ```

- [ ] **Step 2: Transfer APK to Pixel 6**

  Option A — USB cable:
  ```bash
  # Enable "File Transfer" mode on the phone, then:
  adb install build/app/outputs/flutter-apk/app-release.apk
  ```

  Option B — file transfer manually:
  Copy `build/app/outputs/flutter-apk/app-release.apk` to the phone via USB, Google Drive, or email. On the phone, tap the file and allow installation from unknown sources when prompted (Settings → Apps → Special app access → Install unknown apps).

- [ ] **Step 3: Verify on device**

  - App opens to empty state with menu icon
  - Open menu → search "Bishop, CA" → chart appears with scrollable rows
  - Scroll left/right across 7 days
  - Toggle rows on/off in the menu — state persists after closing and reopening app
  - Tap "Grab new data" — loading indicator appears, chart updates
  - Dark mode toggle changes theme

- [ ] **Step 4: Final commit**

  ```bash
  git tag v1.0.0
  git commit --allow-empty -m "release: v1.0.0 — initial Weather.gov scrollable forecast app"
  ```

---

## Self-Review Notes

- **Spec coverage:** All spec requirements mapped — search via Nominatim ✓, 7-day hourly chart ✓, all 7 chart row types ✓, toggle persistence ✓, dark mode ✓, alert banner + detail sheet ✓, 10-location LRU cache ✓, "Grab new data" button ✓, offline banner ✓, empty state ✓
- **Placeholders:** None
- **Type consistency:** `HourlyPeriod`, `WeatherAlert`, `SavedLocation` types used consistently across all tasks. `kAllRows` / `kDefaultRowVisibility` constants shared between provider and drawer. `CacheService.addOrUpdate` returns updated list — caller saves — consistent in both `searchLocation` and `selectLocation`.
- **Wind speed:** Averaged from range in `parseWindSpeed` per spec.
- **Unicode dark mode:** `\u263e` (☾) and `\u2600` (☀) used in AppDrawer, no emoji.
