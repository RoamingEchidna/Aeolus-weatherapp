import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_location.dart';
import '../constants.dart';

class CacheService {
  static const _key = 'saved_locations';
  final SharedPreferences _prefs;

  CacheService(this._prefs);

  List<SavedLocation> loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    final results = <SavedLocation>[];
    for (final e in list) {
      try {
        results.add(SavedLocation.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        // Skip entries that don't match the current format (e.g. after an upgrade).
      }
    }
    return results;
  }

  void saveAll(List<SavedLocation> locations) {
    final encoded = json.encode(locations.map((l) => l.toJson()).toList());
    _prefs.setString(_key, encoded);
  }

  /// Adds or replaces a location, then evicts the oldest if over the limit.
  /// Returns the updated list (does not save — caller must call saveAll).
  List<SavedLocation> addOrUpdate(
      List<SavedLocation> existing, SavedLocation incoming) {
    final updated = existing
        .where((l) => l.displayName != incoming.displayName)
        .toList();
    updated.add(incoming);

    if (updated.length > kMaxSavedLocations) {
      // Evict oldest unpinned first; fall back to oldest pinned if all are pinned.
      final unpinned = updated.where((l) => !l.isPinned).toList()
        ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
      final victim = unpinned.isNotEmpty
          ? unpinned.first
          : (updated..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed))).first;
      updated.remove(victim);
    }

    return updated;
  }
}
