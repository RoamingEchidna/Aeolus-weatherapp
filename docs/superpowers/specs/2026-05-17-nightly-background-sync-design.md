# Nightly Background Sync — Design Spec

**Date:** 2026-05-17

## Goal

Repurpose the "Auto Sync" toggle so that, when enabled, the app automatically fetches fresh weather data for all pinned locations every night around 12:01AM — even when the app is closed.

---

## Behavior

### Toggle ON
- Schedules a nightly background sync task for the next midnight.
- From that point on, the schedule self-perpetuates: each run reschedules the next midnight before doing any work.

### Toggle OFF
- Cancels all pending sync tasks (midnight, 3AM, 6AM).
- Nothing runs until the toggle is turned back on.

### Per-night retry schedule
| Time | Trigger |
|------|---------|
| ~12:01AM | Primary attempt |
| ~3:00AM | Retry if midnight fetch failed |
| ~6:00AM | Final retry if 3AM fetch failed |

- "Failed" means any pinned location returned a network error.
- Midnight next night is always scheduled at the very start of whichever run fires, before any fetch is attempted. This guarantees the schedule continues regardless of crashes or errors.
- Retry slots (3AM, 6AM) are only scheduled if the fetch failed.
- After 6AM, no more retries until the next midnight.

### What gets synced
All pinned locations (same set as the existing `_syncPinned()` logic — pinned, non-Narnia, regardless of cache age since this is a nightly job not a staleness check).

---

## Components

### 1. `workmanager` package
Added to `pubspec.yaml`. The only new dependency. Wraps Android's WorkManager.

### 2. `lib/services/background_sync_service.dart` (new file)
Owns all WorkManager scheduling. Three methods:

- `schedule()` — cancels any existing tasks, then registers a one-time task named `nightly_sync` with an initial delay calculated to hit 12:01AM tonight (or tomorrow if it's already past midnight).
- `cancel()` — cancels tasks named `nightly_sync`, `nightly_sync_3am`, `nightly_sync_6am`.
- `scheduleRetry(String slot)` — registers a one-time task for `slot` (`"3am"` or `"6am"`) with the appropriate delay from now.

Task names used with WorkManager:
- `nightly_sync` — midnight task
- `nightly_sync_3am` — 3AM retry
- `nightly_sync_6am` — 6AM retry

### 3. Top-level worker callback (in `main.dart` or a dedicated `background_worker.dart`)
WorkManager requires a top-level Dart function registered at app startup. This function:

1. Calls `WidgetsFlutterBinding.ensureInitialized()`.
2. Schedules next midnight immediately via `BackgroundSyncService.schedule()`.
3. Reads SharedPreferences — if `syncPinnedOnOpen` key is `false`, returns `true` (success, nothing to do).
4. Loads saved locations from `CacheService`.
5. Filters to pinned, non-Narnia locations.
6. Fetches each using `NwsService` directly (no Provider).
7. If any fetch throws, schedules the appropriate retry slot and returns `false`.
8. Returns `true` on full success.

The worker identifies which slot it's in via the `taskName` argument WorkManager passes, so it knows whether to retry to 3AM or 6AM.

### 4. Changes to `ForecastProvider`
- `syncPinnedOnOpen` bool and `toggleSyncPinnedOnOpen()` are repurposed: the field is kept (same SharedPreferences key) so the toggle state persists, but the value now controls nightly scheduling rather than sync-on-open.
- `toggleSyncPinnedOnOpen()` calls `BackgroundSyncService.schedule()` or `.cancel()` based on the new value.
- `_syncPinned()` is removed (replaced by the background worker).
- The call to `_syncPinned()` in `init()` is removed.
- On `init()`, if `syncPinnedOnOpen` is true, call `BackgroundSyncService.schedule()` — this is a no-op if a task is already registered, ensuring the schedule survives app updates.

### 5. `AndroidManifest.xml`
Add permission:
```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```
WorkManager's own `BroadcastReceiver` (for rescheduling after reboot) is registered automatically by the package — no manual registration needed.

---

## Data flow (worker, headless)

```
WorkManager fires callback
  → ensureInitialized()
  → BackgroundSyncService.schedule() [next midnight, guaranteed]
  → SharedPreferences: check toggle still on
  → CacheService: load pinned locations
  → NwsService: fetch each location (sequential, errors caught per-location)
  → if any error → BackgroundSyncService.scheduleRetry(slot)
  → return success/failure to WorkManager
```

No Flutter UI is shown. No Provider. No `notifyListeners()`.

---

## Error handling

- Per-location fetch errors are caught individually. One bad location doesn't block the others.
- If *any* location fails, a retry is scheduled.
- WorkManager itself may impose a small timing delay (Doze mode) — this is acceptable for a nightly weather refresh.
- The toggle being turned off between scheduling and execution is handled by the SharedPreferences check at the start of the worker.

---

## What is NOT changing

- The drawer UI label ("Auto Sync") and switch position stay the same.
- The SharedPreferences key (`syncPinnedOnOpen`) stays the same — existing user setting is preserved.
- All existing fetch/cache logic in `NwsService` and `CacheService` is reused unchanged.
