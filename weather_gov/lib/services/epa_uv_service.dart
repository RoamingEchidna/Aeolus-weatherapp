import 'dart:convert';
import 'package:http/http.dart' as http;

class EpaUvService {
  final http.Client _client;

  EpaUvService({http.Client? client}) : _client = client ?? http.Client();

  /// Returns peak daily UV index by local date string "yyyy-MM-dd".
  /// Uses the hourly endpoint which covers ~4 days.
  /// Returns empty map if zip is null, request fails, or data is absent.
  Future<Map<String, int>> fetchUvByZip(String? zip) async {
    if (zip == null) return {};
    final zip5 = zip.length >= 5 ? zip.substring(0, 5) : zip;

    try {
      final uri = Uri.parse(
        'https://data.epa.gov/efservice/getEnvirofactsUVHOURLY/ZIP/$zip5/JSON',
      );
      final response = await _client.get(uri, headers: {
        'User-Agent': 'WeatherGovApp/1.0',
        'Accept': 'application/json',
      });
      if (response.statusCode != 200) return {};

      final list = json.decode(response.body) as List<dynamic>;
      // Keep the peak UV value per calendar day.
      final result = <String, int>{};
      for (final entry in list) {
        final m = entry as Map<String, dynamic>;
        // DATE_TIME format: "Apr/10/2026 06 AM"
        final dateTimeStr = m['DATE_TIME'] as String?;
        final uvRaw = m['UV_VALUE'];
        if (dateTimeStr == null || uvRaw == null) continue;
        final dt = _parseEpaDateTime(dateTimeStr);
        if (dt == null) continue;
        final uv = (uvRaw as num).round();
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        if (!result.containsKey(key) || uv > result[key]!) {
          result[key] = uv;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  DateTime? _parseEpaDateTime(String s) {
    // Expected: "Apr/10/2026 06 AM" — only need the date portion.
    final datePart = s.split(' ').first; // "Apr/10/2026"
    final parts = datePart.split('/');
    if (parts.length != 3) return null;
    final month = _months[parts[0]];
    final day = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (month == null || day == null || year == null) return null;
    return DateTime(year, month, day);
  }
}
