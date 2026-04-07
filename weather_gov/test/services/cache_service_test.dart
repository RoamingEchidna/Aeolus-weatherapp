import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_gov/services/cache_service.dart';
import 'package:weather_gov/models/saved_location.dart';

SavedLocation _makeLocation(String name, DateTime lastAccessed) {
  return SavedLocation(
    displayName: name,
    lat: 37.0,
    lon: -118.0,
    lastAccessed: lastAccessed,
    cachedForecast: [],
    cachedAlerts: [],
    cacheTimestamp: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CacheService', () {
    test('loads empty list when nothing cached', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheService(prefs);
      expect(cache.loadAll(), isEmpty);
    });

    test('saves and reloads locations', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheService(prefs);
      final loc = _makeLocation('Bishop, CA', DateTime.utc(2026, 4, 4));
      cache.saveAll([loc]);

      final prefs2 = await SharedPreferences.getInstance();
      final cache2 = CacheService(prefs2);
      final loaded = cache2.loadAll();

      expect(loaded.length, 1);
      expect(loaded.first.displayName, 'Bishop, CA');
    });

    test('evicts oldest by lastAccessed when 11th location added', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheService(prefs);

      final locations = List.generate(
          10, (i) => _makeLocation('City $i', DateTime.utc(2026, 1, i + 1)));
      cache.saveAll(locations);

      final newLoc = _makeLocation('New City', DateTime.utc(2026, 2, 1));
      final updated = cache.addOrUpdate(cache.loadAll(), newLoc);

      expect(updated.length, 10);
      expect(updated.any((l) => l.displayName == 'City 0'), isFalse);
      expect(updated.any((l) => l.displayName == 'New City'), isTrue);
    });

    test('updating existing location replaces it', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheService(prefs);

      final loc = _makeLocation('Bishop, CA', DateTime.utc(2026, 1, 1));
      cache.saveAll([loc]);

      final updated = _makeLocation('Bishop, CA', DateTime.utc(2026, 4, 4));
      final result = cache.addOrUpdate(cache.loadAll(), updated);

      expect(result.length, 1);
      expect(result.first.lastAccessed, DateTime.utc(2026, 4, 4));
    });
  });
}
