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
    return list
        .map((e) => SavedLocation.fromJson(e as Map<String, dynamic>))
        .toList();
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
      updated.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
      updated.removeAt(0); // remove oldest
    }

    return updated;
  }
}
