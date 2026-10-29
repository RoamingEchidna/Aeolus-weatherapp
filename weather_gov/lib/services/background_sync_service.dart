import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

// Dart task names — what the worker callback receives as `taskName`.
const kSyncTaskMidnight = 'nightly_sync';
const kSyncTask3am = 'nightly_sync_3am';
const kSyncTask6am = 'nightly_sync_6am';

// Every sync job carries this tag so they can all be cancelled together.
const kSyncTag = 'nightly_sync_chain';

// Diagnostic keys so the UI can show whether scheduling/execution are
// actually happening on-device, since WorkManager failures are otherwise
// invisible (no logs, no crash reports for a headless background isolate).
const kPrefLastScheduledAt = 'diag_lastScheduledAt';
const kPrefNextScheduledFor = 'diag_nextScheduledFor';
const kPrefLastSyncAttemptAt = 'diag_lastSyncAttemptAt';
const kPrefLastSyncResult = 'diag_lastSyncResult';
const kPrefLastSyncCompletedAt = 'diag_lastSyncCompletedAt';

class BackgroundSyncService {
  /// Schedules the next 12:01 AM sync. Safe to call from inside a running
  /// sync job: each night gets its own unique work name, so registering
  /// tomorrow's job never cancels the one that is currently running.
  /// (Cancelling running work makes the workmanager plugin destroy the
  /// background Dart engine mid-sync.)
  static Future<void> schedule() async {
    final now = DateTime.now();
    var midnight = DateTime(now.year, now.month, now.day + 1, 0, 1);
    if (now.isBefore(DateTime(now.year, now.month, now.day, 0, 1))) {
      midnight = DateTime(now.year, now.month, now.day, 0, 1);
    }
    final delay = midnight.difference(now);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefLastScheduledAt, now.toIso8601String());
    await prefs.setString(kPrefNextScheduledFor, midnight.toIso8601String());

    await Workmanager().registerOneOffTask(
      '${kSyncTaskMidnight}_${_dateKey(midnight)}',
      kSyncTaskMidnight,
      tag: kSyncTag,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Never call this from inside the worker — it would cancel the running job.
  static Future<void> cancel() async {
    await Workmanager().cancelByTag(kSyncTag);
    await removeLegacyTasks();
  }

  /// Builds before per-night work names registered every job under a fixed,
  /// untagged name; clear those out so they don't run alongside the new ones.
  /// App-side only, for the same reason as [cancel].
  static Future<void> removeLegacyTasks() async {
    await Workmanager().cancelByUniqueName(kSyncTaskMidnight);
    await Workmanager().cancelByUniqueName(kSyncTask3am);
    await Workmanager().cancelByUniqueName(kSyncTask6am);
  }

  static Future<void> scheduleRetry(String currentTaskName) async {
    final now = DateTime.now();

    final String nextTask;
    final DateTime target;
    if (currentTaskName == kSyncTaskMidnight) {
      nextTask = kSyncTask3am;
      target = DateTime(now.year, now.month, now.day, 3, 0);
    } else if (currentTaskName == kSyncTask3am) {
      nextTask = kSyncTask6am;
      target = DateTime(now.year, now.month, now.day, 6, 0);
    } else {
      // After the 6AM attempt, no more retries today.
      return;
    }

    final delay = target.isAfter(now) ? target.difference(now) : const Duration(minutes: 1);
    await Workmanager().registerOneOffTask(
      '${nextTask}_${_dateKey(now)}',
      nextTask,
      tag: kSyncTag,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}
