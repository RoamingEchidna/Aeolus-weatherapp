import '../models/saved_location.dart';
import 'nws_service.dart';
import 'openuv_service.dart';
import 'usno_service.dart';

/// Fetches fresh forecast, sun/moon and UV data for one location and merges
/// it with that location's cached copy.
///
/// Shared by [ForecastProvider] and the WorkManager background isolate, so it
/// must stay free of Flutter UI and ChangeNotifier code. Saving the result is
/// left to the caller, since the two save differently.
class LocationRefresher {
  final NwsService _nwsService;
  final UsnoService _usnoService;
  final OpenUvService _openUvService;

  LocationRefresher({
    required NwsService nwsService,
    required UsnoService usnoService,
    required OpenUvService openUvService,
  })  : _nwsService = nwsService,
        _usnoService = usnoService,
        _openUvService = openUvService;

  /// [cached] is the previous copy of this location, if any. Its pin and
  /// postcode are kept, its UV readings are reused instead of refetched, and
  /// its last 24 hours of periods are kept ahead of the new forecast.
  ///
  /// [lastAccessed] defaults to now. The background sync passes the old value
  /// so a refresh doesn't reorder the drawer.
  Future<SavedLocation> refresh({
    required String displayName,
    required double lat,
    required double lon,
    SavedLocation? cached,
    String? postcode,
    DateTime? lastAccessed,
  }) async {
    final now = DateTime.now();

    // USNO needs the time zone offset from NWS, so it runs after NWS.
    final result = await _nwsService.fetchForecast(lat, lon);
    final rawAstroDays = await _usnoService.fetchAstroData(
      lat: lat,
      lon: lon,
      windowStart: now,
      windowEnd: now.add(const Duration(days: 7)),
      tzOffsetHours: result.tzOffsetHours,
    );

    // Fetch UV only for days the cache is missing, plus today.
    final existingUv = <String, int>{
      for (final d in cached?.cachedAstroData ?? const [])
        if (d.uvIndex != null) _dayKey(d.date): d.uvIndex!,
    };
    final uvMap = await _openUvService.fetchUvForWindow(
      lat: lat,
      lon: lon,
      existing: existingUv,
      windowStart: now,
    );
    final astroDays = rawAstroDays.map((d) {
      final uv = uvMap[_dayKey(d.date)];
      return uv != null ? d.copyWith(uvIndex: uv) : d;
    }).toList();

    // Prepend cached periods from the past 24 hours that predate the new fetch.
    final lookback = now.subtract(const Duration(hours: 24));
    final newStart =
        result.periods.isNotEmpty ? result.periods.first.startTime : now;
    final yesterdayPeriods = (cached?.cachedForecast ?? const [])
        .where((p) =>
            !p.startTime.isBefore(lookback) && p.startTime.isBefore(newStart))
        .toList();

    return SavedLocation(
      displayName: displayName,
      lat: lat,
      lon: lon,
      lastAccessed: lastAccessed ?? now,
      cachedForecast: [...yesterdayPeriods, ...result.periods],
      cachedAlerts: result.alerts,
      cacheTimestamp: now,
      cachedAstroData: astroDays,
      isPinned: cached?.isPinned ?? false,
      postcode: postcode ?? cached?.postcode,
      tzOffsetHours: result.tzOffsetHours,
      timeZone: result.timeZone,
    );
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
