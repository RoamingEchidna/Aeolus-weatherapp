# Nightly Background Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "sync on open" behavior with a nightly WorkManager task that fetches fresh weather for all pinned locations at ~12:01AM, with retries at 3AM and 6AM on failure.

**Architecture:** A new `BackgroundSyncService` owns all WorkManager scheduling. A top-level worker callback function (required by WorkManager) runs headlessly — no UI, no Provider — using `NwsService`, `UsnoService`, `OpenUvService`, and `CacheService` directly. `ForecastProvider`'s toggle is repurposed to call `BackgroundSyncService` instead of the old sync-on-open logic.

**Tech Stack:** Flutter, `workmanager` pub package, Android WorkManager, SharedPreferences, existing NwsService/UsnoService/OpenUvService/CacheService.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `pubspec.yaml` | Add `workmanager` dependency |
| Create | `lib/services/background_sync_service.dart` | All WorkManager scheduling logic |
| Create | `lib/background_worker.dart` | Top-level headless worker callback |
| Modify | `lib/main.dart` | Register WorkManager callback at startup |
| Modify | `lib/providers/forecast_provider.dart` | Repurpose toggle, remove old sync-on-open |
| Modify | `android/app/src/main/AndroidManifest.xml` | Add RECEIVE_BOOT_COMPLETED permission |

---

## Task 1: Add `workmanager` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, add:
```yaml
  workmanager: ^0.5.2
```

- [ ] **Step 2: Install it**

Run:
```
flutter pub get
```
Expected: output ends with `Got dependencies!` and no errors.

- [ ] **Step 3: Commit**

```
git add pubspec.yaml pubspec.lock
git commit -m "chore: add workmanager dependency"
```

---

## Task 2: Create `BackgroundSyncService`

**Files:**
- Create: `weather_gov/lib/services/background_sync_service.dart`

- [ ] **Step 1: Create the file**

Create `weather_gov/lib/services/background_sync_service.dart` with this content:

```dart
import 'package:workmanager/workmanager.dart';

const kSyncTaskMidnight = 'nightly_sync';
const kSyncTask3am = 'nightly_sync_3am';
const kSyncTask6am = 'nightly_sync_6am';

class BackgroundSyncService {
  static Future<void> schedule() async {
    // Cancel any existing tasks before scheduling fresh ones.
    await cancel();

    final now = DateTime.now();
    var midnight = DateTime(now.year, now.month, now.day + 1, 0, 1);
    // If it's before 12:01AM, target tonight instead of tomorrow.
    if (now.isBefore(DateTime(now.year, now.month, now.day, 0, 1))) {
      midnight = DateTime(now.year, now.month, now.day, 0, 1);
    }
    final delay = midnight.difference(now);

    await Workmanager().registerOneOffTask(
      kSyncTaskMidnight,
      kSyncTaskMidnight,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kSyncTaskMidnight);
    await Workmanager().cancelByUniqueName(kSyncTask3am);
    await Workmanager().cancelByUniqueName(kSyncTask6am);
  }

  static Future<void> scheduleRetry(String currentTaskName) async {
    final now = DateTime.now();

    if (currentTaskName == kSyncTaskMidnight) {
      // Schedule 3AM retry.
      final target = DateTime(now.year, now.month, now.day, 3, 0);
      final delay = target.isAfter(now) ? target.difference(now) : const Duration(minutes: 1);
      await Workmanager().registerOneOffTask(
        kSyncTask3am,
        kSyncTask3am,
        initialDelay: delay,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } else if (currentTaskName == kSyncTask3am) {
      // Schedule 6AM retry.
      final target = DateTime(now.year, now.month, now.day, 6, 0);
      final delay = target.isAfter(now) ? target.difference(now) : const Duration(minutes: 1);
      await Workmanager().registerOneOffTask(
        kSyncTask6am,
        kSyncTask6am,
        initialDelay: delay,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    }
    // If currentTaskName == kSyncTask6am, no more retries today.
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```
flutter analyze lib/services/background_sync_service.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```
git add weather_gov/lib/services/background_sync_service.dart
git commit -m "feat: add BackgroundSyncService for WorkManager scheduling"
```

---

## Task 3: Create the headless worker callback

**Files:**
- Create: `weather_gov/lib/background_worker.dart`

This function runs when WorkManager fires — no Flutter UI, no Provider. It directly uses the services.

- [ ] **Step 1: Create the file**

Create `weather_gov/lib/background_worker.dart` with this content:

```dart
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/background_sync_service.dart';
import 'services/cache_service.dart';
import 'services/nws_service.dart';
import 'services/usno_service.dart';
import 'services/openuv_service.dart';
import 'models/saved_location.dart';
import 'models/hourly_period.dart';

// This must be a top-level function — WorkManager calls it in an isolate.
@pragma('vm:entry-point')
void backgroundWorkerCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    // Always reschedule next midnight first, before any work.
    await BackgroundSyncService.schedule();

    final prefs = await SharedPreferences.getInstance();

    // If the user turned the toggle off since this was scheduled, stop here.
    final enabled = prefs.getBool('syncPinnedOnOpen') ?? false;
    if (!enabled) return Future.value(true);

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
          allLocations: locations,
          cacheService: cacheService,
          nwsService: nwsService,
          usnoService: usnoService,
          openUvService: openUvService,
          prefs: prefs,
        );
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
  required List<SavedLocation> allLocations,
  required CacheService cacheService,
  required NwsService nwsService,
  required UsnoService usnoService,
  required OpenUvService openUvService,
  required SharedPreferences prefs,
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
```

- [ ] **Step 2: Add missing import**

The file references `Workmanager()` — add the import at the top of the file after line 1:
```dart
import 'package:workmanager/workmanager.dart';
```

- [ ] **Step 3: Verify it compiles**

Run:
```
flutter analyze lib/background_worker.dart
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```
git add weather_gov/lib/background_worker.dart
git commit -m "feat: add headless background worker callback"
```

---

## Task 4: Register WorkManager in `main.dart`

**Files:**
- Modify: `weather_gov/lib/main.dart`

WorkManager must be initialized once at app startup with the callback function.

- [ ] **Step 1: Add imports**

At the top of `main.dart`, add these two imports after the existing imports:
```dart
import 'package:workmanager/workmanager.dart';
import 'background_worker.dart';
```

- [ ] **Step 2: Initialize WorkManager in `main()`**

In `main()`, after `WidgetsFlutterBinding.ensureInitialized();` and before `final prefs = ...`, add:
```dart
  await Workmanager().initialize(backgroundWorkerCallback);
```

The full updated `main()` function should look like:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundWorkerCallback);
  final prefs = await SharedPreferences.getInstance();
  final client = http.Client();

  final provider = ForecastProvider(
    nwsService: NwsService(client: client),
    nominatimService: NominatimService(client: client),
    cacheService: CacheService(prefs),
    usnoService: UsnoService(client: http.Client()),
    epaUvService: OpenUvService(client: client),
    prefs: prefs,
  );
  await provider.init();

  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const WeatherApp(),
    ),
  );
}
```

- [ ] **Step 3: Verify it compiles**

Run:
```
flutter analyze lib/main.dart
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```
git add weather_gov/lib/main.dart
git commit -m "feat: initialize WorkManager at app startup"
```

---

## Task 5: Update `ForecastProvider` — repurpose the toggle

**Files:**
- Modify: `weather_gov/lib/providers/forecast_provider.dart`

- [ ] **Step 1: Add import**

At the top of `forecast_provider.dart`, after the existing imports, add:
```dart
import 'background_sync_service.dart';
```

- [ ] **Step 2: Remove `_syncPinned()` and update `init()`**

Replace the `_syncPinned()` method (lines 65–88) and the call to it in `init()` (line 55) with the updated versions:

Remove this from `init()`:
```dart
    if (syncPinnedOnOpen) _syncPinned();
```

Replace it with:
```dart
    if (syncPinnedOnOpen) BackgroundSyncService.schedule();
```

Delete the entire `_syncPinned()` method:
```dart
  Future<void> _syncPinned() async {
    final now = DateTime.now();
    final stale = savedLocations
        .where((l) => l.isPinned &&
            l.displayName != 'Narnia' &&
            now.difference(l.cacheTimestamp).inMinutes >= 60)
        .toList();
    if (stale.isEmpty) return;
    final current = currentLocation;
    final ordered = [
      if (current != null && stale.any((l) => l.displayName == current.displayName)) current,
      ...stale.where((l) => l.displayName != current?.displayName),
    ];
    isLoading = true;
    notifyListeners();
    for (final loc in ordered) {
      try {
        await _fetchAndSave(loc.displayName, loc.lat, loc.lon, postcode: loc.postcode);
      } catch (_) {}
    }
    isLoading = false;
    notifyListeners();
  }
```

- [ ] **Step 3: Update `toggleSyncPinnedOnOpen()`**

Replace:
```dart
  void toggleSyncPinnedOnOpen() {
    syncPinnedOnOpen = !syncPinnedOnOpen;
    _savePreferences();
    notifyListeners();
  }
```

With:
```dart
  void toggleSyncPinnedOnOpen() {
    syncPinnedOnOpen = !syncPinnedOnOpen;
    _savePreferences();
    if (syncPinnedOnOpen) {
      BackgroundSyncService.schedule();
    } else {
      BackgroundSyncService.cancel();
    }
    notifyListeners();
  }
```

- [ ] **Step 4: Verify it compiles**

Run:
```
flutter analyze lib/providers/forecast_provider.dart
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```
git add weather_gov/lib/providers/forecast_provider.dart
git commit -m "feat: repurpose Auto Sync toggle to schedule nightly WorkManager task"
```

---

## Task 6: Update `AndroidManifest.xml`

**Files:**
- Modify: `weather_gov/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add the boot permission**

In `AndroidManifest.xml`, add this line after the existing `<uses-permission android:name="android.permission.INTERNET"/>` line:
```xml
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

- [ ] **Step 2: Verify the app builds**

Run:
```
flutter build apk --debug
```
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 3: Commit**

```
git add weather_gov/android/app/src/main/AndroidManifest.xml
git commit -m "feat: add RECEIVE_BOOT_COMPLETED permission for WorkManager"
```

---

## Task 7: Manual smoke test on device

- [ ] **Step 1: Install on device**

```
flutter install
```

- [ ] **Step 2: Test toggle ON behavior**
  1. Open the app drawer.
  2. Flip "Auto Sync" ON.
  3. Verify no crash. The toggle should save and the schedule is now set for midnight.

- [ ] **Step 3: Test toggle OFF behavior**
  1. Flip "Auto Sync" OFF.
  2. Verify no crash. WorkManager tasks are cancelled.

- [ ] **Step 4: Test worker fires (fast test)**

Use `adb` to trigger the WorkManager task immediately without waiting until midnight:
```
adb shell am broadcast -a androidx.work.diagnostics.REQUEST_DIAGNOSTICS
```

Or use the WorkManager test helper to trigger the task directly from the Android Studio device inspector, or run:
```
adb shell cmd jobscheduler run -f <package-name> <job-id>
```

Check `adb logcat` for any Dart exceptions from the background isolate.

- [ ] **Step 5: Verify cached data updates**

After the worker runs, open the app and verify the pinned locations show an updated `cacheTimestamp` (visible if you add a temporary debug label, or by checking that the chart data reflects the new fetch time).

- [ ] **Step 6: Final commit if any fixes were needed**

```
git add -A
git commit -m "fix: address smoke test issues"
```
