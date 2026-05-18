import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'services/background_sync_service.dart';
import 'services/cache_service.dart';
import 'services/nws_service.dart';
import 'services/usno_service.dart';
import 'services/notification_service.dart';
import 'services/openuv_service.dart';
import 'models/saved_location.dart';

// This must be a top-level function — WorkManager calls it in an isolate.
@pragma('vm:entry-point')
void backgroundWorkerCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.initialize();

    // Always reschedule next midnight first, before any work.
    await BackgroundSyncService.schedule();

    final prefs = await SharedPreferences.getInstance();

    // If the user turned the toggle off since this was scheduled, stop here.
    final enabled = prefs.getBool('syncPinnedOnOpen') ?? false;
    if (!enabled) return Future.value(true);

    final notificationsEnabled = prefs.getBool('severeWeatherNotifications') ?? false;

    final cacheService = CacheService(prefs);
    final locations = cacheService.loadAll()
        .where((l) => l.isPinned && l.displayName != 'Narnia')
        .toList();

    if (locations.isEmpty) return Future.value(true);

    final client = http.Client();
    final nwsService = NwsService(client: client);
    final usnoService = UsnoService(client: http.Client());
    final openUvService = OpenUvService(client: client);

    // Load UV key from prefs if user set one.
    final uvKey = prefs.getString('openUvApiKey');
    if (uvKey != null) openUvService.setApiKey(uvKey);

    bool anyFailed = false;

    for (final loc in locations) {
      try {
        await _fetchAndSave(
          loc: loc,
          cacheService: cacheService,
          nwsService: nwsService,
          usnoService: usnoService,
          openUvService: openUvService,
        );
        if (notificationsEnabled) {
          final fresh = cacheService.loadAll();
          final updated = fresh.firstWhere(
            (l) => l.displayName == loc.displayName,
            orElse: () => loc,
          );
          await NotificationService.postAlertNotification(
            loc.displayName,
            updated.cachedAlerts,
          );
        }
      } catch (_) {
        anyFailed = true;
      }
    }

    client.close();

    if (anyFailed) {
      await BackgroundSyncService.scheduleRetry(taskName);
      return Future.value(false);
    }
    return Future.value(true);
  });
}

Future<void> _fetchAndSave({
  required SavedLocation loc,
  required CacheService cacheService,
  required NwsService nwsService,
  required UsnoService usnoService,
  required OpenUvService openUvService,
}) async {
  final now = DateTime.now();

  final result = await nwsService.fetchForecast(loc.lat, loc.lon);
  final rawAstroDays = await usnoService.fetchAstroData(
    lat: loc.lat,
    lon: loc.lon,
    windowStart: now,
    windowEnd: now.add(const Duration(days: 7)),
    tzOffsetHours: result.tzOffsetHours,
  );

  // Build existing UV map from cached astro data.
  final existingUv = <String, int>{};
  for (final d in loc.cachedAstroData) {
    if (d.uvIndex != null) {
      final k = '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}';
      existingUv[k] = d.uvIndex!;
    }
  }

  final uvMap = await openUvService.fetchUvForWindow(
    lat: loc.lat,
    lon: loc.lon,
    existing: existingUv,
    windowStart: now,
  );

  final astroDays = rawAstroDays.map((d) {
    final key = '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}';
    final uv = uvMap[key];
    return uv != null ? d.copyWith(uvIndex: uv) : d;
  }).toList();

  final lookback = now.subtract(const Duration(hours: 24));
  final newStart = result.periods.isNotEmpty ? result.periods.first.startTime : now;
  final yesterdayPeriods = loc.cachedForecast
      .where((p) => !p.startTime.isBefore(lookback) && p.startTime.isBefore(newStart))
      .toList();
  final mergedPeriods = [...yesterdayPeriods, ...result.periods];

  final updated = SavedLocation(
    displayName: loc.displayName,
    lat: loc.lat,
    lon: loc.lon,
    lastAccessed: loc.lastAccessed,
    cachedForecast: mergedPeriods,
    cachedAlerts: result.alerts,
    cacheTimestamp: now,
    cachedAstroData: astroDays,
    isPinned: loc.isPinned,
    postcode: loc.postcode,
    tzOffsetHours: result.tzOffsetHours,
    timeZone: result.timeZone,
  );

  // Read fresh list in case a previous iteration updated it.
  final fresh = cacheService.loadAll();
  final merged = cacheService.addOrUpdate(fresh, updated);
  cacheService.saveAll(merged);
}
