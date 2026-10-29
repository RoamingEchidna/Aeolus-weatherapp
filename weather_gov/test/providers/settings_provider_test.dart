import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_gov/constants.dart';
import 'package:weather_gov/providers/settings_provider.dart';
import 'package:weather_gov/services/openuv_service.dart';

Future<SettingsProvider> _makeSettings(
    [Map<String, Object> saved = const {}]) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  return SettingsProvider(prefs: prefs, openUvService: OpenUvService());
}

void main() {
  group('SettingsProvider defaults', () {
    test('graph rows shown, solar and lunar hidden', () async {
      final settings = await _makeSettings();
      expect(settings.visibleRows[kRowTempGroup], isTrue);
      expect(settings.visibleRows[kRowWindGroup], isTrue);
      expect(settings.visibleRows[kRowSolar], isFalse);
      expect(settings.visibleRows[kRowLunar], isFalse);
      expect(settings.isDarkMode, isFalse);
    });
  });

  group('SettingsProvider persistence', () {
    test('toggleRow flips and saves row visibility', () async {
      final settings = await _makeSettings();
      settings.toggleRow(kRowTempGroup);
      expect(settings.visibleRows[kRowTempGroup], isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('row_$kRowTempGroup'), isFalse);
    });

    test('toggleDarkMode flips and saves', () async {
      final settings = await _makeSettings();
      settings.toggleDarkMode();
      expect(settings.isDarkMode, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('isDarkMode'), isTrue);
    });

    test('loads values saved by an earlier app version', () async {
      final settings = await _makeSettings({
        'isDarkMode': true,
        'use24Hour': true,
        'row_$kRowSolar': true,
      });
      expect(settings.isDarkMode, isTrue);
      expect(settings.use24Hour, isTrue);
      expect(settings.visibleRows[kRowSolar], isTrue);
    });

    test('saved row order keeps rows added since it was saved', () async {
      final settings = await _makeSettings({
        'rowOrder': [kRowWindGroup, kRowTempGroup],
      });
      expect(settings.rowOrder.take(2), [kRowWindGroup, kRowTempGroup]);
      expect(settings.rowOrder.toSet(), kAllRows.toSet());
    });
  });
}
