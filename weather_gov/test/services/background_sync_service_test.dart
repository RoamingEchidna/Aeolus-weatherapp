import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_gov/services/background_sync_service.dart';

const _channel = MethodChannel('be.tramckrijte.workmanager/foreground_channel_work_manager');

String _dateKey(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('BackgroundSyncService', () {
    // The worker calls schedule() while its own job is running. Cancelling or
    // REPLACE-ing that running job makes the plugin destroy the background
    // engine mid-sync, so schedule() must only ever touch a future night.
    test('schedule() never cancels anything and books a future night', () async {
      await BackgroundSyncService.schedule();

      expect(calls.where((c) => c.method.startsWith('cancel')), isEmpty);
      final register = calls.singleWhere((c) => c.method == 'registerOneOffTask');
      final args = Map<String, dynamic>.from(register.arguments as Map);

      final prefs = await SharedPreferences.getInstance();
      final next = DateTime.parse(prefs.getString(kPrefNextScheduledFor)!);
      expect(next.isAfter(DateTime.now()), isTrue);
      expect(args['uniqueName'], '${kSyncTaskMidnight}_${_dateKey(next)}');
      expect(args['uniqueName'], isNot(kSyncTaskMidnight));
      expect(args['taskName'], kSyncTaskMidnight);
      expect(args['tag'], kSyncTag);
    });

    test('scheduleRetry() books the next rung under a dated name', () async {
      await BackgroundSyncService.scheduleRetry(kSyncTaskMidnight);
      await BackgroundSyncService.scheduleRetry(kSyncTask3am);
      await BackgroundSyncService.scheduleRetry(kSyncTask6am);

      expect(calls.where((c) => c.method.startsWith('cancel')), isEmpty);
      final registers = calls
          .where((c) => c.method == 'registerOneOffTask')
          .map((c) => Map<String, dynamic>.from(c.arguments as Map))
          .toList();
      final today = _dateKey(DateTime.now());
      expect(registers.map((a) => a['taskName']), [kSyncTask3am, kSyncTask6am]);
      expect(registers.map((a) => a['uniqueName']),
          ['${kSyncTask3am}_$today', '${kSyncTask6am}_$today']);
      expect(registers.every((a) => a['tag'] == kSyncTag), isTrue);
    });

    test('cancel() clears tagged jobs and legacy fixed-name jobs', () async {
      await BackgroundSyncService.cancel();

      expect(calls.any((c) => c.method == 'cancelTaskByTag' &&
          (c.arguments as Map)['tag'] == kSyncTag), isTrue);
      final legacy = calls
          .where((c) => c.method == 'cancelTaskByUniqueName')
          .map((c) => (c.arguments as Map)['uniqueName'])
          .toSet();
      expect(legacy, {kSyncTaskMidnight, kSyncTask3am, kSyncTask6am});
    });
  });
}
