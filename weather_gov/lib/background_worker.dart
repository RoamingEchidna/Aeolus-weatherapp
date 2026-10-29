import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'services/background_sync_service.dart'
    show BackgroundSyncService, kPrefLastSyncAttemptAt, kPrefLastSyncResult, kPrefLastSyncCompletedAt;
import 'services/cache_service.dart';
import 'services/nws_service.dart';
import 'services/usno_service.dart';
import 'services/notification_service.dart';
import 'services/openuv_service.dart';
import 'services/location_refresher.dart';

// This must be a top-level function — WorkManager calls it in an isolate.
@pragma('vm:entry-point')
void backgroundWorkerCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    SharedPreferences? prefs;
    var rescheduled = false;
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // Diagnostic: record that the OS actually invoked this callback, before
      // any work that could throw. If this key never updates on-device, the
      // OS is failing to run the job at all (Doze/battery restrictions/etc.)
      // rather than the sync logic itself failing.
      prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefLastSyncAttemptAt, DateTime.now().toIso8601String());

      // Always reschedule next midnight first, before any work, so a failure
      // below can't break the nightly chain.
      await BackgroundSyncService.schedule();
      rescheduled = true;

      await NotificationService.initialize();

      // If the user turned the toggle off since this was scheduled, stop here.
      final enabled = prefs.getBool('syncPinnedOnOpen') ?? false;
      if (!enabled) {
        await _recordResult(prefs, 'skipped_disabled');
        return Future.value(true);
      }

      final notificationsEnabled = prefs.getBool('severeWeatherNotifications') ?? false;

      final cacheService = CacheService(prefs);
      final locations = cacheService.loadAll().where((l) => l.isPinned).toList();

      if (locations.isEmpty) {
        await _recordResult(prefs, 'skipped_no_pinned_locations');
        return Future.value(true);
      }

      final client = http.Client();
      final openUvService = OpenUvService(client: client);

      // Load UV key from prefs if user set one.
      final uvKey = prefs.getString('openUvApiKey');
      if (uvKey != null) openUvService.setApiKey(uvKey);

      final refresher = LocationRefresher(
        nwsService: NwsService(client: client),
        usnoService: UsnoService(client: http.Client()),
        openUvService: openUvService,
      );

      bool anyFailed = false;

      for (final loc in locations) {
        try {
          final updated = await refresher.refresh(
            displayName: loc.displayName,
            lat: loc.lat,
            lon: loc.lon,
            cached: loc,
            lastAccessed: loc.lastAccessed,
          );
          // Re-read the list before saving in case the app saved meanwhile.
          cacheService.saveAll(
              cacheService.addOrUpdate(cacheService.loadAll(), updated));
          if (notificationsEnabled) {
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

      // Return true even on failure: the 3AM/6AM ladder is the retry
      // mechanism. Returning false would also make WorkManager re-run this
      // job on its own exponential backoff.
      if (anyFailed) {
        await _recordResult(prefs, 'partial_failure');
        await BackgroundSyncService.scheduleRetry(taskName);
        return Future.value(true);
      }
      await _recordResult(prefs, 'success');
      return Future.value(true);
    } catch (e) {
      // Catch-all so an unexpected exception (e.g. plugin init failure in
      // the headless isolate) still leaves a trace instead of the task
      // silently vanishing with no way to tell it ever ran.
      if (prefs != null) await _recordResult(prefs, 'error: $e');
      if (!rescheduled) {
        // Tomorrow's run isn't booked — let WorkManager retry this job so
        // the nightly chain doesn't die.
        return Future.value(false);
      }
      try {
        await BackgroundSyncService.scheduleRetry(taskName);
      } catch (_) {}
      return Future.value(true);
    }
  });
}

Future<void> _recordResult(SharedPreferences prefs, String result) async {
  await prefs.setString(kPrefLastSyncResult, result);
  await prefs.setString(kPrefLastSyncCompletedAt, DateTime.now().toIso8601String());
}
