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
