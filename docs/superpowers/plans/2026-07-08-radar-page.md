# Radar Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Radar button in the app bar opens a page showing an animated NEXRAD reflectivity loop over state/county boundaries, centered on the current location, with disk-cached frames building a 5-hour rolling history.

**Architecture:** A stateless `RadarService` (nearest-station lookup with CONUS-composite fallback, WMS GetCapabilities/GetMap requests), a `RadarFrameCache` (PNG files in the app temp directory, 5-hour eviction), and a `RadarScreen` that owns playback state. One `IconButton` added to `ChartScreen`'s AppBar. No `ForecastProvider` changes.

**Tech Stack:** Flutter, `http` (existing), `shared_preferences` (existing), `path_provider` (NEW dependency), `intl` (existing). Tests use `MockClient` from `package:http/testing.dart` (existing pattern — see `test/services/usno_service_test.dart`).

**Spec:** `docs/superpowers/specs/2026-07-08-radar-page-design.md` — read its "Implementation notes" section before starting. Critical traps: WMS `time=` values must be echoed **verbatim** (never re-serialized through `DateTime`), use `crs=CRS:84` (never `EPSG:4326`), station IDs lowercase in GeoServer URLs, `styles=` always present.

**Working directory:** all paths below are relative to `weather_gov/` (the Flutter project root inside the repo). Run all `flutter` commands from there.

---

### Task 1: Add path_provider dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, after the `flutter_local_notifications: ^18.0.0` line, add:

```yaml
  path_provider: ^2.1.4
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get`
Expected: `Got dependencies!` (or "Changed N dependencies")

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add path_provider dependency for radar frame cache"
```

---

### Task 2: RadarSource, LatLonBox, and capabilities time parsing

**Files:**
- Create: `lib/services/radar_service.dart`
- Test: `test/services/radar_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/services/radar_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/services/radar_service.dart';

const _kCapabilitiesXml = '''
<WMS_Capabilities>
  <Layer>
    <Name>kabr_sr_bref</Name>
    <Title>NEXRAD Level 3 Super Resolution Radar Base Reflectivity</Title>
    <Dimension name="time" default="2026-07-08T18:11:00Z" units="ISO8601">2026-07-08T17:57:07.000Z,2026-07-08T16:13:01.000Z,2026-07-08T18:11:00.000Z</Dimension>
  </Layer>
  <Layer>
    <Name>kabr_sr_bvel</Name>
    <Dimension name="time" default="x" units="ISO8601">2026-07-08T01:01:01.000Z</Dimension>
  </Layer>
</WMS_Capabilities>
''';

void main() {
  group('LatLonBox', () {
    test('around() builds a box of ±half degrees', () {
      final box = LatLonBox.around(37.36, -118.40, 2.0);
      expect(box.minLon, -120.40);
      expect(box.minLat, 35.36);
      expect(box.maxLon, -116.40);
      expect(box.maxLat, 39.36);
      expect(box.bboxParam, '-120.40,35.36,-116.40,39.36');
    });

    test('fractions map lon/lat into 0..1, y inverted', () {
      final box = LatLonBox.around(37.36, -118.40, 2.0);
      expect(box.xFraction(-118.40), closeTo(0.5, 1e-9));
      expect(box.yFraction(37.36), closeTo(0.5, 1e-9));
      expect(box.xFraction(box.minLon), 0.0);
      expect(box.yFraction(box.maxLat), 0.0); // top of image = max lat
    });
  });

  group('RadarSource', () {
    test('station source lowercases ids in layer and URL', () {
      const s = RadarSource.station('KABR');
      expect(s.isComposite, isFalse);
      expect(s.sourceKey, 'kabr');
      expect(s.layerName, 'kabr_sr_bref');
      expect(s.owsBase,
          'https://opengeo.ncep.noaa.gov/geoserver/kabr/ows');
    });

    test('composite source uses conus layer', () {
      const s = RadarSource.composite();
      expect(s.isComposite, isTrue);
      expect(s.sourceKey, 'conus');
      expect(s.layerName, 'conus_bref_qcd');
      expect(s.owsBase,
          'https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows');
    });
  });

  group('RadarService.parseTimeDimension', () {
    test('extracts verbatim timestamps for the right layer, sorted ascending',
        () {
      final times =
          RadarService.parseTimeDimension(_kCapabilitiesXml, 'kabr_sr_bref');
      expect(times, [
        '2026-07-08T16:13:01.000Z',
        '2026-07-08T17:57:07.000Z',
        '2026-07-08T18:11:00.000Z',
      ]);
    });

    test('returns empty list when layer missing', () {
      expect(RadarService.parseTimeDimension(_kCapabilitiesXml, 'nope'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/radar_service_test.dart`
Expected: FAIL — compile error, `radar_service.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/services/radar_service.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Geographic bounding box in CRS:84 (lon/lat) axis order.
class LatLonBox {
  final double minLon, minLat, maxLon, maxLat;
  const LatLonBox(this.minLon, this.minLat, this.maxLon, this.maxLat);

  factory LatLonBox.around(double lat, double lon, double halfDeg) =>
      LatLonBox(lon - halfDeg, lat - halfDeg, lon + halfDeg, lat + halfDeg);

  /// WMS 1.3.0 bbox parameter with CRS:84: minLon,minLat,maxLon,maxLat.
  String get bboxParam =>
      '${minLon.toStringAsFixed(2)},${minLat.toStringAsFixed(2)},'
      '${maxLon.toStringAsFixed(2)},${maxLat.toStringAsFixed(2)}';

  /// Fractional x-position of [lon] within the box (0 = left edge).
  double xFraction(double lon) => (lon - minLon) / (maxLon - minLon);

  /// Fractional y-position of [lat] within the box (0 = TOP edge — image
  /// y grows downward while latitude grows upward).
  double yFraction(double lat) => (maxLat - lat) / (maxLat - minLat);
}

/// A radar imagery source: a specific NEXRAD station, or the CONUS composite.
class RadarSource {
  /// Uppercase station id like 'KABR', or null for the CONUS composite.
  final String? stationId;
  const RadarSource.station(String id) : stationId = id;
  const RadarSource.composite() : stationId = null;

  bool get isComposite => stationId == null;
  String get sourceKey => stationId?.toLowerCase() ?? 'conus';
  String get layerName =>
      isComposite ? 'conus_bref_qcd' : '${stationId!.toLowerCase()}_sr_bref';
  String get owsBase => isComposite
      ? 'https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows'
      : 'https://opengeo.ncep.noaa.gov/geoserver/${stationId!.toLowerCase()}/ows';
}

class RadarService {
  final http.Client _client;
  final SharedPreferences? _prefs;

  static const _headers = {'User-Agent': 'WeatherGovApp/1.0'};
  static const maxStationDistanceKm = 200.0;
  static const _stationsUrl = 'https://api.weather.gov/radar/stations';
  static const _boundariesBase =
      'https://mapservices.weather.noaa.gov/static/services/nws_reference_maps/nws_reference_map/MapServer/WMSServer';

  RadarService({http.Client? client, SharedPreferences? prefs})
      : _client = client ?? http.Client(),
        _prefs = prefs;

  /// Extracts the comma-separated TIME dimension values for [layerName]
  /// from WMS capabilities XML, sorted oldest-first. Values are kept as
  /// verbatim strings — GeoServer requires the exact listed string in
  /// GetMap time= parameters (re-serializing through DateTime changes the
  /// millisecond formatting and yields blank images).
  static List<String> parseTimeDimension(String xml, String layerName) {
    final nameIdx = xml.indexOf('<Name>$layerName</Name>');
    if (nameIdx < 0) return [];
    final dimStart = xml.indexOf('<Dimension name="time"', nameIdx);
    if (dimStart < 0) return [];
    final contentStart = xml.indexOf('>', dimStart) + 1;
    final contentEnd = xml.indexOf('</Dimension>', contentStart);
    if (contentEnd < 0) return [];
    final times = xml
        .substring(contentStart, contentEnd)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    times.sort((a, b) => DateTime.parse(a).compareTo(DateTime.parse(b)));
    return times;
  }
}
```

(`dart:convert`, `dart:math`, `dart:typed_data`, and the `_client`/`_prefs`/URL constants are unused until Tasks 3–4; the analyzer will warn — that's expected and resolves in the next tasks. If you prefer zero warnings at each commit, add the imports/constants in the task that first uses them instead.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/radar_service_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/radar_service.dart test/services/radar_service_test.dart
git commit -m "feat: radar source model, bbox math, WMS time-dimension parsing"
```

---

### Task 3: Nearest-station resolution with composite fallback

**Files:**
- Modify: `lib/services/radar_service.dart`
- Test: `test/services/radar_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/services/radar_service_test.dart`. New imports at top of file:

```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

New canned response constant (top level):

```dart
const _kStationsJson = '''
{
  "features": [
    {
      "geometry": {"type": "Point", "coordinates": [-118.5, 37.4]},
      "properties": {"id": "KNEAR", "stationType": "WSR-88D"}
    },
    {
      "geometry": {"type": "Point", "coordinates": [-100.0, 40.0]},
      "properties": {"id": "KFAR", "stationType": "WSR-88D"}
    },
    {
      "geometry": {"type": "Point", "coordinates": [-118.40, 37.36]},
      "properties": {"id": "TTDWR", "stationType": "TDWR"}
    }
  ]
}
''';
```

New test group inside `main()`:

```dart
  group('RadarService.resolveSource', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    RadarService service(String body, {int status = 200}) => RadarService(
          client: MockClient((_) async => http.Response(body, status)),
          prefs: prefs,
        );

    test('picks nearest WSR-88D station, ignoring closer TDWR', () async {
      final s = await service(_kStationsJson).resolveSource(37.36, -118.40);
      expect(s.stationId, 'KNEAR');
    });

    test('falls back to composite when nearest station > 200 km', () async {
      // (30.0, -90.0) is ~1000+ km from both WSR-88D stations.
      final s = await service(_kStationsJson).resolveSource(30.0, -90.0);
      expect(s.isComposite, isTrue);
    });

    test('falls back to composite on HTTP error, without persisting it',
        () async {
      final s = await service('oops', status: 500).resolveSource(37.36, -118.40);
      expect(s.isComposite, isTrue);
      // Failure must NOT be cached — a later retry should hit the network.
      expect(prefs.getString('radarSource_37.36_-118.40'), isNull);
    });

    test('caches successful resolution and reuses it without a request',
        () async {
      await service(_kStationsJson).resolveSource(37.36, -118.40);
      expect(prefs.getString('radarSource_37.36_-118.40'), 'KNEAR');

      // Second service whose client would fail if called.
      final s2 = await service('boom', status: 500).resolveSource(37.36, -118.40);
      expect(s2.stationId, 'KNEAR');
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/radar_service_test.dart`
Expected: FAIL — `resolveSource` not defined.

- [ ] **Step 3: Implement resolveSource**

Add inside the `RadarService` class in `lib/services/radar_service.dart`:

```dart
  /// Finds the nearest WSR-88D station to (lat, lon). Falls back to the
  /// CONUS composite when the nearest is farther than
  /// [maxStationDistanceKm] or the lookup fails. Successful resolutions
  /// are cached in prefs; failures are never cached so a transient network
  /// error can't permanently lock a location to the composite.
  Future<RadarSource> resolveSource(double lat, double lon) async {
    final cacheKey =
        'radarSource_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
    final cached = _prefs?.getString(cacheKey);
    if (cached != null) {
      return cached == 'conus'
          ? const RadarSource.composite()
          : RadarSource.station(cached);
    }

    try {
      final resp = await _client.get(
        Uri.parse(_stationsUrl),
        headers: {..._headers, 'Accept': 'application/geo+json'},
      );
      if (resp.statusCode != 200) {
        throw Exception('stations error ${resp.statusCode}');
      }
      final features =
          (json.decode(resp.body)['features'] as List<dynamic>? ?? []);

      String? bestId;
      var bestKm = double.infinity;
      for (final f in features) {
        final props = f['properties'] as Map<String, dynamic>? ?? {};
        if (props['stationType'] != 'WSR-88D') continue;
        final coords = f['geometry']?['coordinates'] as List<dynamic>?;
        final id = props['id'] as String?;
        if (coords == null || coords.length < 2 || id == null) continue;
        final km = _haversineKm(
            lat, lon, (coords[1] as num).toDouble(), (coords[0] as num).toDouble());
        if (km < bestKm) {
          bestKm = km;
          bestId = id;
        }
      }

      final source = (bestId != null && bestKm <= maxStationDistanceKm)
          ? RadarSource.station(bestId)
          : const RadarSource.composite();
      await _prefs?.setString(cacheKey, source.stationId ?? 'conus');
      return source;
    } catch (_) {
      return const RadarSource.composite();
    }
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/radar_service_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/radar_service.dart test/services/radar_service_test.dart
git commit -m "feat: nearest NEXRAD station resolution with composite fallback"
```

---

### Task 4: WMS fetch methods (capabilities, frames, boundaries)

**Files:**
- Modify: `lib/services/radar_service.dart`
- Test: `test/services/radar_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Add a new group to `test/services/radar_service_test.dart`. These use a
capturing MockClient to assert the exact request URLs — the URL details
(CRS:84, verbatim time, styles present) are the whole point.

```dart
  group('RadarService WMS requests', () {
    test('fetchAvailableTimes issues GetCapabilities and parses times',
        () async {
      late Uri captured;
      final service = RadarService(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response(_kCapabilitiesXml, 200);
        }),
      );
      final times =
          await service.fetchAvailableTimes(const RadarSource.station('KABR'));
      expect(captured.toString(),
          'https://opengeo.ncep.noaa.gov/geoserver/kabr/ows?service=WMS&version=1.3.0&request=GetCapabilities');
      expect(times.length, 3);
      expect(times.first, '2026-07-08T16:13:01.000Z');
    });

    test('fetchFrame builds a correct GetMap URL with verbatim time',
        () async {
      late Uri captured;
      final service = RadarService(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      final box = LatLonBox.around(37.36, -118.40, 2.0);
      final bytes = await service.fetchFrame(
          const RadarSource.station('KABR'), box, '2026-07-08T16:13:01.000Z');

      expect(bytes, [1, 2, 3]);
      final q = captured.queryParameters;
      expect(q['crs'], 'CRS:84');
      expect(q['bbox'], '-120.40,35.36,-116.40,39.36');
      expect(q['layers'], 'kabr_sr_bref');
      expect(q['styles'], '');
      expect(q['time'], '2026-07-08T16:13:01.000Z');
      expect(q['transparent'], 'true');
      expect(q['width'], '800');
      expect(q['height'], '800');
    });

    test('fetchBoundaries requests states+counties in one call', () async {
      late Uri captured;
      final service = RadarService(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response.bytes([9], 200);
        }),
      );
      final box = LatLonBox.around(37.36, -118.40, 2.0);
      await service.fetchBoundaries(box);

      expect(captured.host, 'mapservices.weather.noaa.gov');
      final q = captured.queryParameters;
      expect(q['layers'], '8,9');
      expect(q['styles'], ',');
      expect(q['crs'], 'CRS:84');
      expect(q['bbox'], '-120.40,35.36,-116.40,39.36');
    });

    test('fetchFrame throws on non-200', () async {
      final service = RadarService(
          client: MockClient((_) async => http.Response('err', 500)));
      final box = LatLonBox.around(37.36, -118.40, 2.0);
      expect(
        () => service.fetchFrame(
            const RadarSource.composite(), box, '2026-07-08T16:13:01.000Z'),
        throwsException,
      );
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/radar_service_test.dart`
Expected: FAIL — `fetchAvailableTimes` / `fetchFrame` / `fetchBoundaries` not defined.

- [ ] **Step 3: Implement the fetch methods**

Add inside the `RadarService` class:

```dart
  /// Lists available frame timestamps (verbatim strings, oldest first).
  Future<List<String>> fetchAvailableTimes(RadarSource source) async {
    final uri = Uri.parse(
        '${source.owsBase}?service=WMS&version=1.3.0&request=GetCapabilities');
    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('GetCapabilities error ${resp.statusCode}');
    }
    return parseTimeDimension(resp.body, source.layerName);
  }

  /// Fetches one reflectivity frame PNG. [time] must be a verbatim string
  /// from [fetchAvailableTimes].
  Future<Uint8List> fetchFrame(
      RadarSource source, LatLonBox bbox, String time) async {
    final uri = Uri.parse('${source.owsBase}?service=WMS&version=1.3.0'
        '&request=GetMap&layers=${source.layerName}&styles='
        '&crs=CRS:84&bbox=${bbox.bboxParam}'
        '&width=800&height=800&format=image/png&transparent=true'
        '&time=$time');
    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('GetMap error ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  /// Fetches the state+county boundaries overlay PNG (transparent
  /// background) for the same bbox as the frames.
  Future<Uint8List> fetchBoundaries(LatLonBox bbox) async {
    final uri = Uri.parse('$_boundariesBase?service=WMS&version=1.3.0'
        '&request=GetMap&layers=8,9&styles=,'
        '&crs=CRS:84&bbox=${bbox.bboxParam}'
        '&width=800&height=800&format=image/png&transparent=true');
    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('boundaries GetMap error ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/radar_service_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/services/radar_service.dart`
Expected: No issues (all imports/constants now used).

- [ ] **Step 6: Commit**

```bash
git add lib/services/radar_service.dart test/services/radar_service_test.dart
git commit -m "feat: WMS capabilities, frame, and boundary fetching for radar"
```

---

### Task 5: RadarFrameCache (disk cache with 5-hour eviction)

**Files:**
- Create: `lib/services/radar_frame_cache.dart`
- Test: `test/services/radar_frame_cache_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/services/radar_frame_cache_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/services/radar_frame_cache.dart';

void main() {
  late Directory tempDir;
  late RadarFrameCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('radar_cache_test');
    cache = RadarFrameCache(dir: tempDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  final bytes = Uint8List.fromList([1, 2, 3]);

  test('saveFrame / loadFrames round-trip, keyed by source and location',
      () async {
    await cache.saveFrame('kabr', 37.36, -118.40, 1000, bytes);
    await cache.saveFrame('kabr', 37.36, -118.40, 2000, bytes);
    await cache.saveFrame('conus', 37.36, -118.40, 3000, bytes); // other source
    await cache.saveFrame('kabr', 40.00, -100.00, 4000, bytes); // other location

    final frames = await cache.loadFrames('kabr', 37.36, -118.40);
    expect(frames.keys.toSet(), {1000, 2000});
    expect(frames[1000], bytes);
  });

  test('boundaries round-trip and survive frame eviction', () async {
    expect(await cache.loadBoundaries(37.36, -118.40), isNull);
    await cache.saveBoundaries(37.36, -118.40, bytes);
    expect(await cache.loadBoundaries(37.36, -118.40), bytes);

    await cache.evictOlderThan(DateTime.now());
    expect(await cache.loadBoundaries(37.36, -118.40), bytes,
        reason: 'boundaries never expire');
  });

  test('evictOlderThan deletes only frames older than cutoff, all locations',
      () async {
    final now = DateTime.now();
    final oldMs = now.subtract(const Duration(hours: 6)).millisecondsSinceEpoch;
    final newMs = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    await cache.saveFrame('kabr', 37.36, -118.40, oldMs, bytes);
    await cache.saveFrame('kabr', 37.36, -118.40, newMs, bytes);
    await cache.saveFrame('conus', 40.00, -100.00, oldMs, bytes);

    await cache.evictOlderThan(now.subtract(const Duration(hours: 5)));

    expect((await cache.loadFrames('kabr', 37.36, -118.40)).keys.toList(),
        [newMs]);
    expect(await cache.loadFrames('conus', 40.00, -100.00), isEmpty);
  });

  test('coordinates are rounded to 2 decimals in keys', () async {
    await cache.saveFrame('kabr', 37.36123, -118.40456, 1000, bytes);
    final frames = await cache.loadFrames('kabr', 37.359, -118.401);
    expect(frames.keys.toList(), [1000]);
  });
}
```

Note: `37.359.toStringAsFixed(2)` → `'37.36'` and `-118.401` → `'-118.40'`, matching `37.36123`/`-118.40456` rounded — that's what the last test verifies.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/radar_frame_cache_test.dart`
Expected: FAIL — compile error, `radar_frame_cache.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/services/radar_frame_cache.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Disk cache for radar frame and boundary PNGs.
///
/// Frames: `radar_{sourceKey}_{lat}_{lon}_{utcMillis}.png` — the location
/// is part of the key because frames are cropped to a bbox centered on it;
/// a frame for one location is never valid for another.
/// Boundaries: `bounds_{lat}_{lon}.png`, never evicted (they don't change).
class RadarFrameCache {
  final Directory? _overrideDir;

  /// [dir] overrides the platform cache directory (used by tests).
  RadarFrameCache({Directory? dir}) : _overrideDir = dir;

  Future<Directory> _dir() async {
    final base = _overrideDir ??
        Directory('${(await getTemporaryDirectory()).path}/radar');
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

  String _coordKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';

  Future<Map<int, Uint8List>> loadFrames(
      String sourceKey, double lat, double lon) async {
    final dir = await _dir();
    final prefix = 'radar_${sourceKey}_${_coordKey(lat, lon)}_';
    final frames = <int, Uint8List>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.png')) continue;
      final millis =
          int.tryParse(name.substring(prefix.length, name.length - 4));
      if (millis == null) continue;
      frames[millis] = await entity.readAsBytes();
    }
    return frames;
  }

  Future<void> saveFrame(String sourceKey, double lat, double lon, int millis,
      Uint8List bytes) async {
    final dir = await _dir();
    await File(
            '${dir.path}/radar_${sourceKey}_${_coordKey(lat, lon)}_$millis.png')
        .writeAsBytes(bytes);
  }

  Future<Uint8List?> loadBoundaries(double lat, double lon) async {
    final dir = await _dir();
    final file = File('${dir.path}/bounds_${_coordKey(lat, lon)}.png');
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> saveBoundaries(double lat, double lon, Uint8List bytes) async {
    final dir = await _dir();
    await File('${dir.path}/bounds_${_coordKey(lat, lon)}.png')
        .writeAsBytes(bytes);
  }

  /// Deletes radar frame files older than [cutoff], across all sources and
  /// locations. Boundary files are untouched.
  Future<void> evictOlderThan(DateTime cutoff) async {
    final dir = await _dir();
    final cutoffMillis = cutoff.millisecondsSinceEpoch;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('radar_') || !name.endsWith('.png')) continue;
      final millis =
          int.tryParse(name.split('_').last.replaceAll('.png', ''));
      if (millis != null && millis < cutoffMillis) {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort; a locked file just gets retried next eviction.
        }
      }
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/radar_frame_cache_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/radar_frame_cache.dart test/services/radar_frame_cache_test.dart
git commit -m "feat: disk-backed radar frame cache with 5-hour eviction"
```

---

### Task 6: RadarScreen (load sequence, stacked display, playback)

UI task — no widget tests (matches existing repo convention: screens are
manually verified; services are unit-tested). Verified by analyzer here and
the manual pass in Task 8.

**Files:**
- Create: `lib/ui/radar_screen.dart`

- [ ] **Step 1: Write the screen**

Create `lib/ui/radar_screen.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_location.dart';
import '../providers/forecast_provider.dart';
import '../services/radar_frame_cache.dart';
import '../services/radar_service.dart';

class RadarScreen extends StatefulWidget {
  final SavedLocation location;
  const RadarScreen({super.key, required this.location});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  static const _speedsMs = [800, 400, 200];
  static const _speedLabels = ['0.5×', '1×', '2×'];
  static const _maxAge = Duration(hours: 5);

  late final LatLonBox _bbox;
  final _cache = RadarFrameCache();
  RadarService? _service;

  Uint8List? _boundaries;
  final Map<int, Uint8List> _frames = {}; // utcMillis -> png bytes
  List<int> _times = []; // sorted keys of _frames

  int _index = 0;
  bool _playing = false;
  int _speedIdx = 1;
  Timer? _timer;

  bool _loading = true;
  String? _error; // fatal: nothing to show
  String? _notice; // non-fatal: showing cached frames

  @override
  void initState() {
    super.initState();
    _bbox = LatLonBox.around(widget.location.lat, widget.location.lon, 2.0);
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _rebuildTimes() {
    _times = _frames.keys.toList()..sort();
    if (_index >= _times.length) _index = _times.isEmpty ? 0 : _times.length - 1;
  }

  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _playing = false;
    });

    final lat = widget.location.lat;
    final lon = widget.location.lon;

    try {
      // Evict stale frames from disk AND memory (refresh path re-enters here).
      final cutoff = DateTime.now().subtract(_maxAge);
      await _cache.evictOlderThan(cutoff);
      _frames.removeWhere(
          (millis, _) => millis < cutoff.millisecondsSinceEpoch);

      final prefs = await SharedPreferences.getInstance();
      _service ??= RadarService(prefs: prefs);
      var source = await _service!.resolveSource(lat, lon);

      // Boundaries: memory -> disk -> network; tolerate total failure.
      _boundaries ??= await _cache.loadBoundaries(lat, lon);
      if (_boundaries == null) {
        try {
          _boundaries = await _service!.fetchBoundaries(_bbox);
          await _cache.saveBoundaries(lat, lon, _boundaries!);
        } catch (_) {
          // Radar without boundaries is still usable.
        }
      }

      // Paint whatever is already cached before any network wait.
      _frames.addAll(await _cache.loadFrames(source.sourceKey, lat, lon));
      _rebuildTimes();
      if (_frames.isNotEmpty && mounted) {
        setState(() {
          _loading = false;
          _index = _times.length - 1;
        });
      }

      // List available frames; a dead station falls back to composite.
      List<String> available;
      try {
        available = await _service!.fetchAvailableTimes(source);
      } catch (_) {
        if (source.isComposite) rethrow;
        source = const RadarSource.composite();
        _frames
          ..clear()
          ..addAll(await _cache.loadFrames(source.sourceKey, lat, lon));
        _rebuildTimes();
        available = await _service!.fetchAvailableTimes(source);
      }

      // Fetch missing frames newest-first so current conditions paint in
      // one round-trip; older frames backfill behind it.
      final missing = available
          .where((t) =>
              !_frames.containsKey(DateTime.parse(t).millisecondsSinceEpoch))
          .toList()
          .reversed
          .toList();
      for (final t in missing) {
        try {
          final bytes = await _service!.fetchFrame(source, _bbox, t);
          final millis = DateTime.parse(t).millisecondsSinceEpoch;
          _frames[millis] = bytes;
          await _cache.saveFrame(source.sourceKey, lat, lon, millis, bytes);
          _rebuildTimes();
          if (mounted) {
            setState(() {
              _loading = false;
              _index = _times.length - 1;
            });
          }
        } catch (_) {
          // Skip failed frames; the loop plays what it has.
        }
      }

      if (!mounted) return;
      if (_frames.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No radar data available for this location.';
        });
        return;
      }
      setState(() => _loading = false);
      _startPlayback();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_frames.isEmpty) {
          _error = "Couldn't load radar data.";
        } else {
          _notice = "Couldn't fetch latest radar — showing cached frames.";
          _startPlayback();
        }
      });
    }
  }

  void _startPlayback() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: _speedsMs[_speedIdx]),
      (_) {
        if (_times.isEmpty) return;
        setState(() => _index = (_index + 1) % _times.length);
      },
    );
    setState(() => _playing = true);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    setState(() => _playing = false);
  }

  void _cycleSpeed() {
    setState(() => _speedIdx = (_speedIdx + 1) % _speedsMs.length);
    if (_playing) _startPlayback();
  }

  String _frameLabel(int millis, bool use24Hour) {
    final local = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
        .add(Duration(hours: widget.location.tzOffsetHours));
    return DateFormat(use24Hour ? 'MMM d, HH:mm' : 'MMM d, h:mm a')
        .format(local);
  }

  @override
  Widget build(BuildContext context) {
    final use24Hour = context.watch<ForecastProvider>().use24Hour;
    final currentFrame =
        _times.isEmpty ? null : _frames[_times[_index]];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.location.displayName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh radar',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : Column(
              children: [
                if (_notice != null)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Text(
                      _notice!,
                      style: Theme.of(context).textTheme.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (currentFrame == null)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else ...[
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      // Fixed light background in both themes: NOAA's
                      // boundary strokes are dark and vanish on dark surfaces.
                      color: const Color(0xFFE0E0E0),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            if (_boundaries != null)
                              Positioned.fill(
                                child: Image.memory(
                                  _boundaries!,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                              ),
                            Positioned.fill(
                              child: Image.memory(
                                currentFrame,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                            ),
                            Positioned(
                              left: _bbox.xFraction(widget.location.lon) *
                                      constraints.maxWidth -
                                  5,
                              top: _bbox.yFraction(widget.location.lat) *
                                      constraints.maxHeight -
                                  5,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primary,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _frameLabel(_times[_index], use24Hour),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                              _playing ? Icons.pause : Icons.play_arrow),
                          onPressed:
                              _playing ? _pause : _startPlayback,
                        ),
                        Expanded(
                          child: Slider(
                            value: _index.toDouble(),
                            min: 0,
                            max: (_times.length - 1)
                                .clamp(1, 1 << 30)
                                .toDouble(),
                            divisions:
                                _times.length > 1 ? _times.length - 1 : 1,
                            onChangeStart: (_) => _pause(),
                            onChanged: _times.length > 1
                                ? (v) =>
                                    setState(() => _index = v.round())
                                : null,
                          ),
                        ),
                        TextButton(
                          onPressed: _cycleSpeed,
                          child: Text(_speedLabels[_speedIdx]),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/ui/radar_screen.dart`
Expected: No issues.

- [ ] **Step 3: Run full test suite (regression check)**

Run: `flutter test`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/radar_screen.dart
git commit -m "feat: radar screen with playback loop, scrubber, and speed control"
```

---

### Task 7: App bar entry point

**Files:**
- Modify: `lib/ui/chart_screen.dart`

- [ ] **Step 1: Add the radar button**

In `lib/ui/chart_screen.dart`, add the import at the top with the other
relative imports:

```dart
import 'radar_screen.dart';
```

Then in the `Scaffold`'s `AppBar` (currently ending at `centerTitle: false,`),
add an `actions` list so it reads:

```dart
      appBar: AppBar(
        title: location == null
            ? const Text('Weather Forecast')
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      location.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ..._locationTimeParts(location, provider.use24Hour, context),
                ],
              ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.radar),
            tooltip: 'Radar',
            onPressed: location == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RadarScreen(location: location),
                      ),
                    ),
          ),
        ],
      ),
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/ui/chart_screen.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/chart_screen.dart
git commit -m "feat: radar button in app bar opens radar screen"
```

---

### Task 8: Final verification

- [ ] **Step 1: Full analyzer and test suite**

Run: `flutter analyze` (whole project) and `flutter test`
Expected: No issues; all tests pass. Fix anything found before proceeding.

- [ ] **Step 2: Manual on-device checklist**

Build (`flutter build apk --release`), install, and verify:

1. Radar button appears right of the local time; disabled with no location.
2. Open radar for a location near a NEXRAD site (e.g. a city) — loop loads,
   newest frame appears quickly, then older frames fill in.
3. Dot marker sits at the searched location; state/county lines visible in
   both light and dark mode.
4. Play/pause, scrubbing (pauses playback), and speed cycling (0.5×/1×/2×)
   all work; timestamp label tracks the current frame.
5. Refresh fetches only new frames (fast when nothing new exists).
6. Kill the app, reopen radar — cached frames paint instantly before any
   network activity.
7. A location > 200 km from any NEXRAD site (e.g. middle of Nevada/Pacific
   coast gaps) falls back to the composite without an error.

- [ ] **Step 3: Commit any fixes, then hand off**

Report results to the user before building any release APK — release/version
decisions are theirs.
