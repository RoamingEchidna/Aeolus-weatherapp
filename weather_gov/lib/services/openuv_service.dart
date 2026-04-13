import 'dart:convert';
import 'package:http/http.dart' as http;
import '../secrets.dart';

class OpenUvService {
  final http.Client _client;
  String? _overrideKey; // set at runtime from SharedPreferences
  static const _base = 'https://api.openuv.io/api/v1/uv';

  OpenUvService({http.Client? client}) : _client = client ?? http.Client();

  void setApiKey(String? key) => _overrideKey = (key != null && key.trim().isNotEmpty) ? key.trim() : null;

  Map<String, String> get _headers => {
    'x-access-token': _overrideKey ?? kOpenUvApiKey,
    'Accept': 'application/json',
  };

  /// Fetches uv_max for a single date at the given lat/lon.
  /// [date] is local midnight for the desired day.
  /// Returns null if the request fails.
  Future<int?> fetchUvMaxForDate(double lat, double lon, DateTime date) async {
    try {
      // Request UV for noon on the target date in UTC (approximate).
      final noon = DateTime(date.year, date.month, date.day, 12);
      final dt = noon.toUtc().toIso8601String();
      final uri = Uri.parse(
        '$_base?lat=${lat.toStringAsFixed(4)}&lng=${lon.toStringAsFixed(4)}&dt=${Uri.encodeComponent(dt)}',
      );
      final response = await _client.get(uri, headers: _headers);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return null;
      final uvMax = result['uv_max'];
      if (uvMax == null) return null;
      return (uvMax as num).round();
    } catch (_) {
      return null;
    }
  }

  /// Fetches UV index for the given days, using smart caching:
  /// - Days already in [existing] are kept unless they are today (always refresh today).
  /// - Missing days are fetched (up to 7 days from today).
  /// Returns a map of "yyyy-MM-dd" → uv_max.
  Future<Map<String, int>> fetchUvForWindow({
    required double lat,
    required double lon,
    required Map<String, int> existing,
    required DateTime windowStart,
    int days = 7,
  }) async {
    final result = Map<String, int>.from(existing);
    final today = DateTime.now();
    final todayKey = _key(today);

    final futures = <Future<void>>[];

    for (int i = 0; i < days; i++) {
      final date = DateTime(windowStart.year, windowStart.month, windowStart.day + i);
      final k = _key(date);
      // Always refresh today; fetch if missing.
      if (k == todayKey || !result.containsKey(k)) {
        futures.add(fetchUvMaxForDate(lat, lon, date).then((uv) {
          if (uv != null) result[k] = uv;
        }));
      }
    }

    await Future.wait(futures);
    return result;
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
