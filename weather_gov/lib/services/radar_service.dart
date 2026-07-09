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
