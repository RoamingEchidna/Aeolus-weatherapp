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
    // Collect all calendar dates in the window.
    final dates = <DateTime>[];
    var d = DateTime.utc(windowStart.year, windowStart.month, windowStart.day);
    final lastDay = DateTime.utc(windowEnd.year, windowEnd.month, windowEnd.day);
    while (!d.isAfter(lastDay)) {
      dates.add(d);
      d = d.add(const Duration(days: 1));
    }

    // Fire all requests in parallel.
    return Future.wait(
      dates.map((date) => _fetchOneDay(date, lat, lon, tzOffsetHours)),
    );
  }

  Future<AstroDay> _fetchOneDay(
      DateTime date, double lat, double lon, int tzOffsetHours) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
        '$_base?date=$dateStr&coords=$lat,$lon&tz=$tzOffsetHours');
    try {
      final resp = await _client.get(uri);
      if (resp.statusCode != 200) return AstroDay.sentinel(date);

      final body = json.decode(resp.body) as Map<String, dynamic>;
      final data = (body['properties'] as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

      DateTime? parseEvent(List<dynamic> list, String phen) {
        for (final e in list) {
          final entry = e as Map<String, dynamic>;
          if (entry['phen'] == phen) {
            final parts = (entry['time'] as String).split(':');
            return DateTime.utc(
              date.year, date.month, date.day,
              int.parse(parts[0]), int.parse(parts[1]),
            );
          }
        }
        return null;
      }

      final sundata  = data['sundata']  as List<dynamic>? ?? [];
      final moondata = data['moondata'] as List<dynamic>? ?? [];

      final curPhase = data['curphase'] as String?;
      final closest = data['closestphase'] as Map<String, dynamic>?;
      String? moonPhase = curPhase;
      if (closest != null) {
        final closestDateStr = closest['date'] as String?;
        if (closestDateStr != null) {
          final closestDate = DateTime.tryParse(closestDateStr);
          if (closestDate != null &&
              closestDate.year == date.year &&
              closestDate.month == date.month &&
              closestDate.day == date.day) {
            moonPhase = closest['phase'] as String?;
          }
        }
      }

      return AstroDay(
        date: date,
        beginCivilTwilight: parseEvent(sundata,  'Begin Civil Twilight'),
        sunrise:             parseEvent(sundata,  'Rise'),
        solarNoon:           parseEvent(sundata,  'Upper Transit'),
        sunset:              parseEvent(sundata,  'Set'),
        endCivilTwilight:    parseEvent(sundata,  'End Civil Twilight'),
        moonrise:            parseEvent(moondata, 'Rise'),
        moonset:             parseEvent(moondata, 'Set'),
        moonPhase:           moonPhase,
      );
    } catch (_) {
      return AstroDay.sentinel(date);
    }
  }
}
