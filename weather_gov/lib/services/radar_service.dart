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
}
