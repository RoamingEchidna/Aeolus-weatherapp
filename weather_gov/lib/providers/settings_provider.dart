import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/openuv_service.dart';
import '../services/background_sync_service.dart';

/// User preferences and background-sync status, persisted in
/// SharedPreferences. The background worker reads some of these keys
/// directly ('syncPinnedOnOpen', 'severeWeatherNotifications',
/// 'openUvApiKey'), so don't rename them.
class SettingsProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  final OpenUvService _openUvService;

  Map<String, bool> visibleRows = Map.from(kDefaultRowVisibility);
  List<String> rowOrder = List.from(kAllRows);
  bool isDarkMode = false;
  bool use24Hour = false;
  bool useMetric = false;
  bool syncPinnedOnOpen = false;
  bool severeWeatherNotifications = false;

  SettingsProvider({
    required SharedPreferences prefs,
    required OpenUvService openUvService,
  })  : _prefs = prefs,
        _openUvService = openUvService {
    _loadPreferences();
  }

  /// Registers background work. Kept out of the constructor because it
  /// calls into WorkManager, which isn't available in unit tests.
  void init() {
    BackgroundSyncService.removeLegacyTasks();
    if (syncPinnedOnOpen) BackgroundSyncService.schedule();
  }

  String? get openUvApiKey => _prefs.getString('openUvApiKey');

  // Background-sync diagnostics, so the on/off toggle isn't a black box —
  // see background_worker.dart for where these get written.
  String? get lastSyncScheduledAt => _prefs.getString(kPrefLastScheduledAt);
  String? get nextSyncScheduledFor => _prefs.getString(kPrefNextScheduledFor);
  String? get lastSyncAttemptAt => _prefs.getString(kPrefLastSyncAttemptAt);
  String? get lastSyncResult => _prefs.getString(kPrefLastSyncResult);
  String? get lastSyncCompletedAt => _prefs.getString(kPrefLastSyncCompletedAt);

  static const _batteryWarningCooldown = Duration(days: 15);

  /// Whether the battery-optimization warning dialog should be shown again
  /// (i.e. it either hasn't been shown before, or it's been 15+ days).
  bool get shouldShowBatteryWarning {
    final raw = _prefs.getString('lastBatteryWarningShownAt');
    final last = raw != null ? DateTime.tryParse(raw) : null;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _batteryWarningCooldown;
  }

  void recordBatteryWarningShown() {
    _prefs.setString('lastBatteryWarningShownAt', DateTime.now().toIso8601String());
  }

  /// Re-reads diagnostic keys from disk. Needed because the background
  /// isolate writes them independently of this provider's in-memory state.
  Future<void> refreshSyncDiagnostics() async {
    await _prefs.reload();
    notifyListeners();
  }

  Future<void> setOpenUvApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove('openUvApiKey');
      _openUvService.setApiKey(null);
    } else {
      await _prefs.setString('openUvApiKey', trimmed);
      _openUvService.setApiKey(trimmed);
    }
    notifyListeners();
  }

  void reorderRow(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final row = rowOrder.removeAt(oldIndex);
    rowOrder.insert(newIndex, row);
    _prefs.setStringList('rowOrder', rowOrder);
    notifyListeners();
  }

  void _loadPreferences() {
    isDarkMode = _prefs.getBool('isDarkMode') ?? false;
    use24Hour = _prefs.getBool('use24Hour') ?? false;
    useMetric = _prefs.getBool('useMetric') ?? false;
    syncPinnedOnOpen = _prefs.getBool('syncPinnedOnOpen') ?? false;
    severeWeatherNotifications = _prefs.getBool('severeWeatherNotifications') ?? false;
    for (final row in kAllRows) {
      final saved = _prefs.getBool('row_$row');
      if (saved != null) visibleRows[row] = saved;
    }
    final savedKey = _prefs.getString('openUvApiKey');
    if (savedKey != null) _openUvService.setApiKey(savedKey);
    final savedOrder = _prefs.getStringList('rowOrder');
    if (savedOrder != null) {
      // Merge: keep saved order, append any new rows not yet in saved order.
      final merged = [...savedOrder.where(kAllRows.contains),
                      ...kAllRows.where((r) => !savedOrder.contains(r))];
      rowOrder = merged;
    }
  }

  void _savePreferences() {
    _prefs.setBool('isDarkMode', isDarkMode);
    _prefs.setBool('use24Hour', use24Hour);
    _prefs.setBool('useMetric', useMetric);
    _prefs.setBool('syncPinnedOnOpen', syncPinnedOnOpen);
    _prefs.setBool('severeWeatherNotifications', severeWeatherNotifications);
    for (final entry in visibleRows.entries) {
      _prefs.setBool('row_${entry.key}', entry.value);
    }
  }

  void toggleRow(String rowName) {
    visibleRows[rowName] = !(visibleRows[rowName] ?? true);
    _savePreferences();
    notifyListeners();
  }

  void toggleDarkMode() {
    isDarkMode = !isDarkMode;
    _savePreferences();
    notifyListeners();
  }

  void toggle24Hour() {
    use24Hour = !use24Hour;
    _savePreferences();
    notifyListeners();
  }

  void toggleMetric() {
    useMetric = !useMetric;
    _savePreferences();
    notifyListeners();
  }

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

  void toggleSevereWeatherNotifications() {
    severeWeatherNotifications = !severeWeatherNotifications;
    _savePreferences();
    notifyListeners();
  }
}
