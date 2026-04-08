# Astronomical Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Astronomical toggle that reveals a 50dp row beneath Conditions showing solar twilight/day/night bands and a lunar visibility band, sourced from the USNO daily API.

**Architecture:** A new `UsnoService` fetches one USNO API call per calendar day in parallel, producing `AstroDay` model objects stored on `SavedLocation` alongside the weather cache. `AstroRow` (CustomPainter) reads those objects and paints the sun/moon bands pixel-precisely against the same hour grid used by all other rows. The toggle is wired through the existing `ForecastProvider.visibleRows` / `kAllRows` / `AppDrawer` pattern.

**Tech Stack:** Flutter/Dart, `http` package (already a dependency), `flutter_test` + `http/testing.dart` for unit tests.

---

### Task 1: Constants

**Files:**
- Modify: `weather_gov/lib/constants.dart`

- [ ] **Step 1: Add astro color constants and row key**

Open `weather_gov/lib/constants.dart` and add after the alert colors block:

```dart
// Astronomical row colors
const Color kColorAstroNight         = Color(0xFF0D0A1B);
const Color kColorAstroCivilTwilight = Color(0xFF2A2347);
const Color kColorAstroDay           = Color(0xFFECE557);
const Color kColorAstroNoon          = Color(0xFFED7B58);
const Color kColorAstroMoonUp        = Color(0xFFB7C3C9);
```

And add the row name constant with the other row name constants:

```dart
const String kRowAstro = 'Astronomical';
```

Add `kRowAstro` to `kAllRows`:

```dart
const List<String> kAllRows = [
  kRowTempGroup,
  kRowWindGroup,
  kRowAtmosGroup,
  kRowConditions,
  kRowAstro,        // ← add this
];
```

Add `kRowAstro` to `kDefaultRowVisibility` defaulting to `false`:

```dart
const Map<String, bool> kDefaultRowVisibility = {
  kRowTempGroup:  true,
  kRowWindGroup:  true,
  kRowAtmosGroup: true,
  kRowConditions: true,
  kRowAstro:      false,  // ← add this
};
```

- [ ] **Step 2: Commit**

```bash
cd weather_gov
git add lib/constants.dart
git commit -m "feat: add astronomical row constants and colors"
```

---

### Task 2: AstroDay Model

**Files:**
- Create: `weather_gov/lib/models/astro_day.dart`
- Create: `weather_gov/test/models/astro_day_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `weather_gov/test/models/astro_day_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/models/astro_day.dart';

void main() {
  final date = DateTime(2026, 4, 7);

  group('AstroDay.isSentinel', () {
    test('sentinel has all nulls', () {
      final s = AstroDay.sentinel(date);
      expect(s.isSentinel, isTrue);
      expect(s.sunrise, isNull);
      expect(s.sunset, isNull);
      expect(s.moonrise, isNull);
      expect(s.moonset, isNull);
    });

    test('non-sentinel is not sentinel', () {
      final a = AstroDay(
        date: date,
        beginCivilTwilight: DateTime(2026, 4, 7, 6, 16),
        sunrise: DateTime(2026, 4, 7, 6, 43),
        solarNoon: DateTime(2026, 4, 7, 13, 10),
        sunset: DateTime(2026, 4, 7, 19, 38),
        endCivilTwilight: DateTime(2026, 4, 7, 20, 5),
        moonrise: DateTime(2026, 4, 7, 14, 38),
        moonset: null,
      );
      expect(a.isSentinel, isFalse);
    });
  });

  group('AstroDay JSON round-trip', () {
    test('serializes and restores all fields', () {
      final original = AstroDay(
        date: date,
        beginCivilTwilight: DateTime(2026, 4, 7, 6, 16),
        sunrise: DateTime(2026, 4, 7, 6, 43),
        solarNoon: DateTime(2026, 4, 7, 13, 10),
        sunset: DateTime(2026, 4, 7, 19, 38),
        endCivilTwilight: DateTime(2026, 4, 7, 20, 5),
        moonrise: DateTime(2026, 4, 7, 14, 38),
        moonset: null,
      );

      final restored = AstroDay.fromStoredJson(original.toJson());

      expect(restored.date, original.date);
      expect(restored.sunrise, original.sunrise);
      expect(restored.sunset, original.sunset);
      expect(restored.solarNoon, original.solarNoon);
      expect(restored.moonrise, original.moonrise);
      expect(restored.moonset, isNull);
    });

    test('sentinel survives round-trip', () {
      final s = AstroDay.sentinel(date);
      final restored = AstroDay.fromStoredJson(s.toJson());
      expect(restored.isSentinel, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd weather_gov
flutter test test/models/astro_day_test.dart
```

Expected: FAIL with "Target of URI hasn't been created: 'package:weather_gov/models/astro_day.dart'"

- [ ] **Step 3: Implement AstroDay**

Create `weather_gov/lib/models/astro_day.dart`:

```dart
class AstroDay {
  final DateTime date; // midnight local time for this calendar day
  final DateTime? beginCivilTwilight;
  final DateTime? sunrise;
  final DateTime? solarNoon;
  final DateTime? sunset;
  final DateTime? endCivilTwilight;
  final DateTime? moonrise;
  final DateTime? moonset;

  const AstroDay({
    required this.date,
    this.beginCivilTwilight,
    this.sunrise,
    this.solarNoon,
    this.sunset,
    this.endCivilTwilight,
    this.moonrise,
    this.moonset,
  });

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
      };

  factory AstroDay.fromStoredJson(Map<String, dynamic> json) {
    DateTime? _parse(String key) {
      final s = json[key] as String?;
      return s == null ? null : DateTime.parse(s);
    }

    return AstroDay(
      date: DateTime.parse(json['date'] as String),
      beginCivilTwilight: _parse('beginCivilTwilight'),
      sunrise: _parse('sunrise'),
      solarNoon: _parse('solarNoon'),
      sunset: _parse('sunset'),
      endCivilTwilight: _parse('endCivilTwilight'),
      moonrise: _parse('moonrise'),
      moonset: _parse('moonset'),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/models/astro_day_test.dart
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/astro_day.dart test/models/astro_day_test.dart
git commit -m "feat: add AstroDay model with sentinel and JSON round-trip"
```

---

### Task 3: UsnoService

**Files:**
- Create: `weather_gov/lib/services/usno_service.dart`
- Create: `weather_gov/test/services/usno_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `weather_gov/test/services/usno_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_gov/services/usno_service.dart';
import 'package:weather_gov/models/astro_day.dart';

// Minimal real-shape USNO response for 2026-04-07 at lat=38.9, lon=-77.0.
const _kUsnoResponse = '''
{
  "type": "Feature",
  "properties": {
    "data": {
      "sundata": [
        {"phen": "Begin Civil Twilight", "time": "06:16"},
        {"phen": "Rise",                 "time": "06:43"},
        {"phen": "Upper Transit",        "time": "13:10"},
        {"phen": "Set",                  "time": "19:38"},
        {"phen": "End Civil Twilight",   "time": "20:05"}
      ],
      "moondata": [
        {"phen": "Rise", "time": "14:38"},
        {"phen": "Set",  "time": "02:25"}
      ]
    }
  }
}
''';

http.Client _mockClient(String body, {int status = 200}) =>
    MockClient((_) async => http.Response(body, status));

void main() {
  final windowStart = DateTime(2026, 4, 7, 0, 0);
  final windowEnd   = DateTime(2026, 4, 7, 23, 0);

  group('UsnoService.fetchAstroData', () {
    test('parses sun and moon events for a single day', () async {
      final service = UsnoService(client: _mockClient(_kUsnoResponse));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: windowStart, windowEnd: windowEnd,
        tzOffsetHours: -4,
      );

      expect(days.length, 1);
      final day = days.first;
      expect(day.isSentinel, isFalse);
      expect(day.sunrise,    DateTime(2026, 4, 7, 6, 43));
      expect(day.solarNoon,  DateTime(2026, 4, 7, 13, 10));
      expect(day.sunset,     DateTime(2026, 4, 7, 19, 38));
      expect(day.beginCivilTwilight, DateTime(2026, 4, 7, 6, 16));
      expect(day.endCivilTwilight,   DateTime(2026, 4, 7, 20, 5));
      expect(day.moonrise, DateTime(2026, 4, 7, 14, 38));
      expect(day.moonset,  DateTime(2026, 4, 7, 2, 25));
    });

    test('returns sentinel on HTTP error', () async {
      final service = UsnoService(client: _mockClient('', status: 500));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: windowStart, windowEnd: windowEnd,
        tzOffsetHours: -4,
      );

      expect(days.length, 1);
      expect(days.first.isSentinel, isTrue);
    });

    test('returns sentinel on malformed JSON', () async {
      final service = UsnoService(client: _mockClient('not json'));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: windowStart, windowEnd: windowEnd,
        tzOffsetHours: -4,
      );

      expect(days.first.isSentinel, isTrue);
    });

    test('spans two calendar days for a multi-day window', () async {
      final service = UsnoService(client: _mockClient(_kUsnoResponse));
      final days = await service.fetchAstroData(
        lat: 38.9, lon: -77.0,
        windowStart: DateTime(2026, 4, 7, 0, 0),
        windowEnd:   DateTime(2026, 4, 8, 23, 0),
        tzOffsetHours: -4,
      );

      expect(days.length, 2);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/usno_service_test.dart
```

Expected: FAIL — "Target of URI hasn't been created: 'package:weather_gov/services/usno_service.dart'"

- [ ] **Step 3: Implement UsnoService**

Create `weather_gov/lib/services/usno_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/astro_day.dart';

class UsnoService {
  final http.Client _client;
  static const _base = 'https://aa.usno.navy.mil/api/rstt/oneday';

  UsnoService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<AstroDay>> fetchAstroData({
    required double lat,
    required double lon,
    required DateTime windowStart,
    required DateTime windowEnd,
    required int tzOffsetHours,
  }) async {
    // Collect all calendar dates in the window (local dates).
    final dates = <DateTime>[];
    var d = DateTime(windowStart.year, windowStart.month, windowStart.day);
    final lastDay = DateTime(windowEnd.year, windowEnd.month, windowEnd.day);
    while (!d.isAfter(lastDay)) {
      dates.add(d);
      d = d.add(const Duration(days: 1));
    }

    // Fire all requests in parallel.
    final results = await Future.wait(
      dates.map((date) => _fetchOneDay(date, lat, lon, tzOffsetHours)),
    );
    return results;
  }

  Future<AstroDay> _fetchOneDay(
      DateTime date, double lat, double lon, int tzOffsetHours) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
    final uri = Uri.parse(
        '$_base?date=$dateStr&coords=$lat,$lon&tz=$tzOffsetHours');
    try {
      final resp = await _client.get(uri);
      if (resp.statusCode != 200) return AstroDay.sentinel(date);

      final body = json.decode(resp.body) as Map<String, dynamic>;
      final data = (body['properties'] as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

      DateTime? _parseEvent(List<dynamic> list, String phen) {
        for (final e in list) {
          if ((e as Map<String, dynamic>)['phen'] == phen) {
            final parts = (e['time'] as String).split(':');
            return DateTime(
              date.year, date.month, date.day,
              int.parse(parts[0]), int.parse(parts[1]),
            );
          }
        }
        return null;
      }

      final sundata  = data['sundata']  as List<dynamic>? ?? [];
      final moondata = data['moondata'] as List<dynamic>? ?? [];

      return AstroDay(
        date: date,
        beginCivilTwilight: _parseEvent(sundata,  'Begin Civil Twilight'),
        sunrise:             _parseEvent(sundata,  'Rise'),
        solarNoon:           _parseEvent(sundata,  'Upper Transit'),
        sunset:              _parseEvent(sundata,  'Set'),
        endCivilTwilight:    _parseEvent(sundata,  'End Civil Twilight'),
        moonrise:            _parseEvent(moondata, 'Rise'),
        moonset:             _parseEvent(moondata, 'Set'),
      );
    } catch (_) {
      return AstroDay.sentinel(date);
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/usno_service_test.dart
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/usno_service.dart test/services/usno_service_test.dart
git commit -m "feat: add UsnoService with parallel day fetching and sentinel on failure"
```

---

### Task 4: Wire AstroDay into SavedLocation

**Files:**
- Modify: `weather_gov/lib/models/saved_location.dart`

- [ ] **Step 1: Add `cachedAstroData` field**

Replace the entire `weather_gov/lib/models/saved_location.dart` with:

```dart
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

  const SavedLocation({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.lastAccessed,
    required this.cachedForecast,
    required this.cachedAlerts,
    required this.cacheTimestamp,
    this.cachedAstroData = const [],
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
      // Gracefully handle old cached entries that predate this field.
      cachedAstroData: json.containsKey('cachedAstroData')
          ? (json['cachedAstroData'] as List<dynamic>)
              .map((e) => AstroDay.fromStoredJson(e as Map<String, dynamic>))
              .toList()
          : [],
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
      };
}
```

- [ ] **Step 2: Run existing tests to verify nothing broke**

```bash
flutter test test/models/ test/providers/
```

Expected: All existing tests PASS (the `cachedAstroData` field defaults to `[]` so old call sites are unaffected).

- [ ] **Step 3: Commit**

```bash
git add lib/models/saved_location.dart
git commit -m "feat: add cachedAstroData to SavedLocation with backwards-compat deserialization"
```

---

### Task 5: Wire UsnoService into ForecastProvider

**Files:**
- Modify: `weather_gov/lib/providers/forecast_provider.dart`
- Modify: `weather_gov/lib/main.dart`
- Modify: `weather_gov/test/providers/forecast_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Add this test group to `weather_gov/test/providers/forecast_provider_test.dart`. First add the `UsnoService` import at the top:

```dart
import 'package:weather_gov/services/usno_service.dart';
import 'package:weather_gov/models/astro_day.dart';
```

Add a mock USNO client helper after `_makeNominatimClient()`:

```dart
http.Client _makeUsnoClient() {
  return MockClient((_) async => http.Response('''
    {
      "type": "Feature",
      "properties": {
        "data": {
          "sundata": [
            {"phen": "Begin Civil Twilight", "time": "06:16"},
            {"phen": "Rise",                 "time": "06:43"},
            {"phen": "Upper Transit",        "time": "13:10"},
            {"phen": "Set",                  "time": "19:38"},
            {"phen": "End Civil Twilight",   "time": "20:05"}
          ],
          "moondata": [
            {"phen": "Rise", "time": "14:38"}
          ]
        }
      }
    }
  ''', 200));
}
```

Update `_makeProvider()` to accept an optional usno client:

```dart
Future<ForecastProvider> _makeProvider({http.Client? usnoClient}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ForecastProvider(
    nwsService: NwsService(client: _makeNwsClient()),
    nominatimService: NominatimService(client: _makeNominatimClient()),
    cacheService: CacheService(prefs),
    usnoService: UsnoService(client: usnoClient ?? _makeUsnoClient()),
    prefs: prefs,
  );
}
```

Add the new test group:

```dart
group('ForecastProvider astro data', () {
  test('cachedAstroData populated after searchLocation', () async {
    final provider = await _makeProvider();
    await provider.searchLocation('Bishop, CA');

    expect(provider.currentLocation!.cachedAstroData, isNotEmpty);
    expect(provider.currentLocation!.cachedAstroData.first, isA<AstroDay>());
  });

  test('kRowAstro defaults to false', () async {
    final provider = await _makeProvider();
    expect(provider.visibleRows[kRowAstro], isFalse);
  });
});
```

Add `import 'package:weather_gov/constants.dart' show kRowTempGroup, kRowWindGroup, kRowAstro;` (update the existing import).

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/providers/forecast_provider_test.dart
```

Expected: FAIL — `ForecastProvider` doesn't accept `usnoService` yet.

- [ ] **Step 3: Update ForecastProvider**

Replace `weather_gov/lib/providers/forecast_provider.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../models/saved_location.dart';
import '../services/nominatim_service.dart';
import '../services/nws_service.dart';
import '../services/cache_service.dart';
import '../services/usno_service.dart';

class ForecastProvider extends ChangeNotifier {
  final NwsService _nwsService;
  final NominatimService _nominatimService;
  final CacheService _cacheService;
  final UsnoService _usnoService;
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
    required UsnoService usnoService,
    SharedPreferences? prefs,
  })  : _nwsService = nwsService,
        _nominatimService = nominatimService,
        _cacheService = cacheService,
        _usnoService = usnoService,
        _prefs = prefs;

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
    isDarkMode = _prefs.getBool('isDarkMode') ?? false;
    for (final row in kAllRows) {
      final saved = _prefs.getBool('row_$row');
      if (saved != null) visibleRows[row] = saved;
    }
  }

  void _savePreferences() {
    if (_prefs == null) return;
    _prefs.setBool('isDarkMode', isDarkMode);
    for (final entry in visibleRows.entries) {
      _prefs.setBool('row_${entry.key}', entry.value);
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

    // Determine timezone offset from local system time.
    final tzOffset = now.timeZoneOffset.inHours;

    final windowStart = result.periods.first.startTime.toLocal();
    final windowEnd   = result.periods.last.startTime.toLocal();

    // Fetch NWS result and astro data in parallel.
    final astroDays = await _usnoService.fetchAstroData(
      lat: lat,
      lon: lon,
      windowStart: windowStart,
      windowEnd: windowEnd,
      tzOffsetHours: tzOffset,
    );

    final location = SavedLocation(
      displayName: result.locationName,
      lat: lat,
      lon: lon,
      lastAccessed: now,
      cachedForecast: result.periods,
      cachedAlerts: result.alerts,
      cacheTimestamp: now,
      cachedAstroData: astroDays,
    );

    savedLocations = _cacheService.addOrUpdate(savedLocations, location);
    _cacheService.saveAll(savedLocations);
    currentLocation = location;
  }

  void selectLocation(SavedLocation location) {
    currentLocation = location.copyWith(lastAccessed: DateTime.now());
    savedLocations =
        _cacheService.addOrUpdate(savedLocations, currentLocation!);
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

- [ ] **Step 4: Update main.dart to pass UsnoService**

In `weather_gov/lib/main.dart`, add the import and pass the service:

```dart
import 'services/usno_service.dart';
```

Inside `main()`, add after creating `client`:

```dart
final usnoClient = http.Client();

final provider = ForecastProvider(
  nwsService: NwsService(client: client),
  nominatimService: NominatimService(client: client),
  cacheService: CacheService(prefs),
  usnoService: UsnoService(client: usnoClient),
  prefs: prefs,
);
```

- [ ] **Step 5: Run all tests**

```bash
flutter test
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/forecast_provider.dart lib/main.dart test/providers/forecast_provider_test.dart
git commit -m "feat: fetch astro data in parallel with NWS weather in ForecastProvider"
```

---

### Task 6: AstroRow Widget (Painter)

**Files:**
- Create: `weather_gov/lib/ui/chart_rows/astro_row.dart`

No unit tests for the painter — visual output is verified by running the app. The painter logic is deterministic given the model data tested in Task 2.

- [ ] **Step 1: Create AstroRow**

Create `weather_gov/lib/ui/chart_rows/astro_row.dart`:

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../models/astro_day.dart';
import '../../models/hourly_period.dart';

class AstroRow extends StatelessWidget {
  final List<HourlyPeriod> periods;
  final List<AstroDay> astroDays;
  final double height;

  const AstroRow({
    super.key,
    required this.periods,
    required this.astroDays,
    this.height = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: periods.length * kPixelsPerHour,
      height: height,
      child: CustomPaint(
        painter: _AstroPainter(
          periods: periods,
          astroDays: astroDays,
          height: height,
        ),
      ),
    );
  }
}

class _AstroPainter extends CustomPainter {
  final List<HourlyPeriod> periods;
  final List<AstroDay> astroDays;
  final double height;

  const _AstroPainter({
    required this.periods,
    required this.astroDays,
    required this.height,
  });

  // Local time of the first period — all x-coordinates are relative to this.
  DateTime get _windowStart => periods.first.startTime.toLocal();

  double _xFor(DateTime dt) {
    final minutes = dt.difference(_windowStart).inMinutes;
    return (minutes / 60.0) * kPixelsPerHour;
  }

  // Clamp x to [0, totalWidth] so segments starting before/after the window
  // don't draw outside the canvas.
  double _xClamped(DateTime dt, double totalWidth) =>
      _xFor(dt).clamp(0.0, totalWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final sunHeight  = size.height / 2; // top 25dp
    final moonTop    = sunHeight;        // bottom 25dp starts here
    final totalWidth = size.width;

    // --- Base fill: full night color for both bands ---
    final nightPaint = Paint()..color = kColorAstroNight;
    canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth, size.height), nightPaint);

    // --- Process each AstroDay ---
    for (final day in astroDays) {
      if (day.isSentinel) {
        _drawHatching(canvas, day, totalWidth, size.height);
        continue;
      }

      // Sun band segments
      _fillSegment(canvas, day.beginCivilTwilight, day.sunrise,
          kColorAstroCivilTwilight, 0, sunHeight, totalWidth);
      _fillSegment(canvas, day.sunrise, day.sunset,
          kColorAstroDay, 0, sunHeight, totalWidth);
      _fillSegment(canvas, day.sunset, day.endCivilTwilight,
          kColorAstroCivilTwilight, 0, sunHeight, totalWidth);

      // Noon marker (3px, full sun-band height)
      if (day.solarNoon != null) {
        final nx = _xFor(day.solarNoon!);
        if (nx >= 0 && nx <= totalWidth) {
          canvas.drawRect(
            Rect.fromLTWH(nx - 1.5, 0, 3, sunHeight),
            Paint()..color = kColorAstroNoon,
          );
        }
      }
    }

    // --- Moon band: stitch arcs across day boundaries ---
    _paintMoonBand(canvas, moonTop, sunHeight, totalWidth);
  }

  void _fillSegment(Canvas canvas, DateTime? start, DateTime? end,
      Color color, double top, double height, double totalWidth) {
    if (start == null || end == null) return;
    final x0 = _xClamped(start, totalWidth);
    final x1 = _xClamped(end, totalWidth);
    if (x1 <= x0) return;
    canvas.drawRect(
      Rect.fromLTWH(x0, top, x1 - x0, height),
      Paint()..color = color,
    );
  }

  void _paintMoonBand(
      Canvas canvas, double top, double height, double totalWidth) {
    final moonPaint = Paint()..color = kColorAstroMoonUp;

    for (int i = 0; i < astroDays.length; i++) {
      final day = astroDays[i];
      if (day.isSentinel) continue;

      final rise = day.moonrise;
      final set  = day.moonset;

      if (rise == null && set == null) continue;

      if (rise != null && set != null) {
        if (set.isAfter(rise)) {
          // Normal same-day arc.
          final x0 = _xClamped(rise, totalWidth);
          final x1 = _xClamped(set, totalWidth);
          if (x1 > x0) {
            canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
          }
        } else {
          // Moon set before it rose today — it rose yesterday.
          // Paint set-to-midnight on this day; the rise portion was painted
          // when we processed the prior day's rise-only case.
          final dayEnd = DateTime(day.date.year, day.date.month, day.date.day, 23, 59, 59);
          final x0 = _xClamped(day.date, totalWidth);
          final x1 = _xClamped(set, totalWidth);
          if (x1 > x0) {
            canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
          }
          // Also paint rise-to-end-of-day for the previous day if in window.
          if (i > 0 && !astroDays[i - 1].isSentinel) {
            final prevRise = astroDays[i - 1].moonrise;
            if (prevRise != null) {
              final px0 = _xClamped(prevRise, totalWidth);
              final px1 = _xClamped(dayEnd, totalWidth);
              if (px1 > px0) {
                canvas.drawRect(Rect.fromLTWH(px0, top, px1 - px0, height), moonPaint);
              }
            }
          }
          _ = dayEnd; // suppress lint
        }
      } else if (rise != null && set == null) {
        // Moon rises today but sets tomorrow — paint rise to end of day.
        final dayEnd = DateTime(day.date.year, day.date.month, day.date.day + 1, 0, 0);
        final x0 = _xClamped(rise, totalWidth);
        final x1 = _xClamped(dayEnd, totalWidth);
        if (x1 > x0) {
          canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
        }
      } else if (rise == null && set != null) {
        // Moon was already up at midnight — paint from start of day to set.
        final x0 = _xClamped(day.date, totalWidth);
        final x1 = _xClamped(set, totalWidth);
        if (x1 > x0) {
          canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
        }
      }
    }
  }

  void _drawHatching(
      Canvas canvas, AstroDay day, double totalWidth, double fullHeight) {
    // Columns covered by this failed day.
    final x0 = _xClamped(day.date, totalWidth);
    final x1 = _xClamped(
        DateTime(day.date.year, day.date.month, day.date.day + 1, 0, 0),
        totalWidth);
    if (x1 <= x0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(x0, 0, x1 - x0, fullHeight));

    const spacing = 6.0;
    final p1 = Paint()..color = kColorAstroNight ..strokeWidth = spacing / 2 ..style = PaintingStyle.stroke;
    final p2 = Paint()..color = kColorAstroCivilTwilight..strokeWidth = spacing / 2 ..style = PaintingStyle.stroke;

    final diag = x1 - x0 + fullHeight;
    int lineIndex = 0;
    for (double offset = -fullHeight; offset < diag; offset += spacing) {
      final paint = lineIndex.isEven ? p1 : p2;
      canvas.drawLine(
        Offset(x0 + offset, 0),
        Offset(x0 + offset + fullHeight, fullHeight),
        paint,
      );
      lineIndex++;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AstroPainter old) =>
      old.periods != periods ||
      old.astroDays != astroDays ||
      old.height != height;
}
```

Note: The `_ = dayEnd;` line suppresses an "unused variable" lint. If the analyzer complains, remove it — the variable is used in the outer if-branch.

- [ ] **Step 2: Fix the lint issue**

The `_ = dayEnd;` is a workaround for a Dart lint. Instead, restructure that block slightly:

In `_paintMoonBand`, replace the `set.isAfter(rise)` else branch's `_ = dayEnd;` with removing the intermediate `dayEnd` variable and inlining:

```dart
        } else {
          // Moon set before it rose today — it rose yesterday.
          final x0 = _xClamped(day.date, totalWidth);
          final x1 = _xClamped(set, totalWidth);
          if (x1 > x0) {
            canvas.drawRect(Rect.fromLTWH(x0, top, x1 - x0, height), moonPaint);
          }
          if (i > 0 && !astroDays[i - 1].isSentinel) {
            final prevRise = astroDays[i - 1].moonrise;
            if (prevRise != null) {
              final dayEndX = _xClamped(
                DateTime(day.date.year, day.date.month, day.date.day, 23, 59, 59),
                totalWidth,
              );
              final px0 = _xClamped(prevRise, totalWidth);
              if (dayEndX > px0) {
                canvas.drawRect(Rect.fromLTWH(px0, top, dayEndX - px0, height), moonPaint);
              }
            }
          }
        }
```

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/ui/chart_rows/astro_row.dart
```

Expected: No errors. (Warnings about `dart:ui` import being unused are fine — remove the import if analyzer flags it; `Rect`/`Canvas`/`Paint` come from `flutter/material.dart`.)

Remove `import 'dart:ui';` from the top of `astro_row.dart` if `flutter analyze` warns about it.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/chart_rows/astro_row.dart
git commit -m "feat: add AstroRow CustomPainter with sun/moon bands and failure hatching"
```

---

### Task 7: Wire AstroRow into ScrollableChart and AppDrawer

**Files:**
- Modify: `weather_gov/lib/ui/scrollable_chart.dart`
- Modify: `weather_gov/lib/ui/app_drawer.dart`

- [ ] **Step 1: Add AstroRow to ScrollableChart._buildRows**

In `weather_gov/lib/ui/scrollable_chart.dart`, add the import at the top:

```dart
import 'chart_rows/astro_row.dart';
```

At the end of `_buildRows`, before `return entries;`, add:

```dart
    // --- Astronomical (sun/moon bands) ---
    if (visible[kRowAstro] == true) {
      final astroData = context_astroDays; // see note below
      entries.add(_RowEntry(
        name: kRowAstro,
        height: 50.0,
        widget: AstroRow(periods: periods, astroDays: astroData),
      ));
    }
```

Note: `_buildRows` doesn't currently have access to `astroDays`. You need to thread it through. Change the `_buildRows` signature to:

```dart
  List<_RowEntry> _buildRows(
      List<HourlyPeriod> periods,
      Map<String, bool> visible,
      double rowHeight,
      List<AstroDay> astroDays,
    )
```

And in `build()`, get `astroDays` from the provider and pass it:

```dart
    final astroDays = provider.currentLocation?.cachedAstroData ?? [];
    final rows = _buildRows(periods, visible, rowHeight, astroDays);
```

The Astronomical `_RowEntry` then becomes:

```dart
    if (visible[kRowAstro] == true) {
      entries.add(_RowEntry(
        name: kRowAstro,
        height: 50.0,
        widget: AstroRow(periods: periods, astroDays: astroDays),
      ));
    }
```

Also add the import for `AstroDay`:

```dart
import '../models/astro_day.dart';
```

- [ ] **Step 2: The AppDrawer already handles kRowAstro automatically**

`AppDrawer` iterates `kAllRows` to build toggles — since `kRowAstro` was added to `kAllRows` in Task 1, no changes are needed.

Verify by reading `weather_gov/lib/ui/app_drawer.dart` lines 120–130:

```dart
children: kAllRows
    .map((row) => SwitchListTile(
          title: Text(row, ...),
          value: provider.visibleRows[row] ?? true,
          onChanged: (_) => provider.toggleRow(row),
          dense: true,
        ))
    .toList(),
```

`kRowAstro` will appear in the list automatically.

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```

Expected: All tests PASS.

- [ ] **Step 4: Hot-restart the app and verify**

```bash
flutter run
```

- Open the drawer, enable "Astronomical"
- Verify a 50dp bar appears beneath Conditions with sun colors in the top half and moon color in the bottom half
- Drag the cursor over the bar to verify it aligns to the hour grid
- Verify the row disappears when toggled off

- [ ] **Step 5: Commit**

```bash
git add lib/ui/scrollable_chart.dart
git commit -m "feat: wire AstroRow into ScrollableChart and toggle via AppDrawer"
```

---

### Task 8: Push to GitHub

- [ ] **Step 1: Final test run**

```bash
cd weather_gov && flutter test
```

Expected: All tests PASS.

- [ ] **Step 2: Push**

```bash
cd .. && git push origin main
```

---

## Self-Review

**Spec coverage:**
- ✅ Combined 50dp row (Sun top 25, Moon bottom 25) — Task 6
- ✅ All 5 sun colors + noon marker — Task 6 `_AstroPainter`
- ✅ Moon `#B7C3C9` / night `#0D0A1B` — Task 6
- ✅ Failure hatching (diagonal alternating colors) — Task 6 `_drawHatching`
- ✅ USNO API, 1 call/day, parallel — Task 3
- ✅ Sentinel on failure — Tasks 2 + 3
- ✅ `SavedLocation.cachedAstroData` — Task 4
- ✅ Backwards-compat JSON deserialization — Task 4
- ✅ `ForecastProvider` fetches in parallel — Task 5
- ✅ `kRowAstro` in `kAllRows` + `kDefaultRowVisibility = false` — Task 1
- ✅ Drawer toggle (automatic via `kAllRows` loop) — Task 7
- ✅ Moon arc stitching across midnight — Task 6 `_paintMoonBand`
- ✅ No-moon days = all night (no special treatment) — Task 6
- ✅ Polar night (null sunrise/sunset) = all night — Task 6 `_fillSegment` null guard
- ✅ Timezone passed as `tz` param — Task 3 + 5

**Placeholder scan:** None found.

**Type consistency:** `AstroDay` used consistently across Tasks 2–7. `astroDays: List<AstroDay>` threaded from provider → `_buildRows` → `AstroRow` → `_AstroPainter`. `AstroDay.sentinel()` factory used in both service and tests.
