# Debugging Nightly Background Sync

The "Auto Sync" row in the app drawer shows two diagnostic lines whenever the toggle is on:

```
Last attempt: <time> (<result>)
Next scheduled: <time>
```

These come straight from `SharedPreferences` keys written by the background worker
([`background_worker.dart`](../weather_gov/lib/background_worker.dart)) and the scheduler
([`background_sync_service.dart`](../weather_gov/lib/services/background_sync_service.dart)):

| Key | Written | Meaning |
|---|---|---|
| `diag_lastSyncAttemptAt` | First line inside the worker, before any work | The OS actually invoked the callback at this time |
| `diag_lastSyncResult` | Last line of every code path in the worker | How the run ended |
| `diag_lastSyncCompletedAt` | Alongside the result | When it finished (not currently shown in the UI) |
| `diag_nextScheduledFor` | Inside `BackgroundSyncService.schedule()` | The next midnight run WorkManager has registered |

If `diag_lastSyncResult` was never written after an attempt, the drawer falls back to showing
`(pending)` — that's the symptom, not a distinct status the code ever sets.

## The real cause of the permanent `(pending)` (fixed 2026-10-29)

The worker's first step was `BackgroundSyncService.schedule()`, which called `cancel()` on the
`nightly_sync` unique work name — the job that was *currently running* — and then re-registered
that same name with `ExistingWorkPolicy.replace`, which cancels running work too. When WorkManager
cancels a running job, the workmanager plugin's `BackgroundWorker.onStopped()` destroys the
background Flutter engine, killing the sync seconds after it started. The attempt timestamp was
already written, the result never was, so every night ended at `(pending)` with no data fetched.
The 3 AM / 6 AM retries had the same self-cancel.

Fix: every job is now registered under a per-date unique name (`nightly_sync_YYYYMMDD`,
`nightly_sync_3am_YYYYMMDD`, …) with the tag `nightly_sync_chain`, so booking tomorrow never touches
tonight's running job. `cancel()` (app-side only, never from the worker) cancels by tag.
`test/services/background_sync_service_test.dart` guards against regressing this.

## Earlier theory: request timeouts

Every network call in the sync path (`NwsService`, `UsnoService`, `OpenUvService`) used to have
no timeout. A single hung request could block the worker indefinitely; Android's WorkManager
eventually kills a background isolate that overruns its execution window, and that kill happens
from *outside* the Dart code, so the `try`/`catch` in the worker never runs and
`diag_lastSyncResult` never gets written. The result was a permanent `(pending)` with no retry
ever scheduled. The fix adds a 1-minute `.timeout()` to every HTTP call in the sync path, so a
stalled request always resolves (as a thrown `TimeoutException` or an internally-absorbed
failure) well within WorkManager's limit.

## Scenarios you're likely to see now

### 1. Clean success
```
Last attempt: <T> (success)
Next scheduled: <T+1 day, 00:01>
```
Every pinned location fetched fully within the timeout. Normal night.

### 2. A location's forecast fetch times out → retry ladder engages
`NwsService.fetchForecast` doesn't catch its own exceptions — a `TimeoutException` propagates up
to the per-location `try/catch` in the worker, marks that run `anyFailed = true`, and schedules a
3 AM (or 6 AM) retry:
```
Last attempt: <T> (partial_failure)
Next scheduled: <T+1 day, 00:01>
```
**Gotcha:** `diag_nextScheduledFor` only ever reflects the self-perpetuating midnight chain — it
is *not* updated when a 3 AM/6 AM retry task is registered. So after a `partial_failure` at
12:01 AM, the drawer will say "next scheduled: tomorrow midnight" even though the real next
attempt is ~3 AM tonight. Don't read the "Next scheduled" line as "the next time anything will
run" when the result says `partial_failure`.

### 3. Astro/UV data times out, but the run still reports success (silent degradation)
`UsnoService` and `OpenUvService` already had their own internal `try/catch` that swallows
per-request failures and substitutes a sentinel astro day or a `null` UV value. A timeout in
either of these is caught internally, not by the worker's per-location `catch` — so it does
**not** flip `anyFailed`, no retry is scheduled, and the run still reports:
```
Last attempt: <T> (success)
Next scheduled: <T+1 day, 00:01>
```
The forecast for that night updated fine, but the astro/UV data for one or more days may be
missing (sentinel), and the debug line gives no hint of that. This is expected, existing
behavior for these two services — the timeout fix doesn't change what happens once a request
times out, only guarantees the app finds out about it within a minute instead of hanging forever.

### 4. A genuine bug (not a hang) throws
Anything that throws outside the network layer — a JSON parse error, a cache read/write failure,
a plugin-init failure in the headless isolate — is still caught by the worker's top-level
`catch (e)` and recorded verbatim:
```
Last attempt: <T> (error: <exception text>)
Next scheduled: <T+1 day, 00:01>
```
This path was never affected by the hang/timeout bug and isn't changed by this fix; it's included
here because it's the other way a run can end besides success/partial_failure/pending.

### 5. Residual risk: many pinned locations, widespread outage
Locations are fetched **sequentially**, and each location's own requests can each burn up to the
full 1-minute timeout (NWS's 3 endpoints run in parallel per location, so that part is capped at
~1 minute; USNO/OpenUV requests are also parallel internally). In the worst case — every request
for every location times out — total worker runtime is roughly `(number of pinned locations) × 1
minute`. WorkManager's execution ceiling is around 10 minutes, so this is only a real concern with
very large pinned-location lists (8-10+) combined with a total network outage. If `(pending)`
ever reappears, this is the first thing to check: how many locations are pinned, and whether the
outage was total (all requests dead) rather than partial.
