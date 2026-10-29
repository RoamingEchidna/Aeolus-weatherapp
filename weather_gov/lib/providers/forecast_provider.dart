import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_location.dart';
import '../services/nominatim_service.dart';
export '../services/nominatim_service.dart' show SuggestionResult, NominatimService;
import '../services/nws_service.dart';
import '../services/cache_service.dart';
import '../services/usno_service.dart';
import '../services/openuv_service.dart';
import '../services/location_refresher.dart';

/// Saved locations and their forecasts: search, fetch, pin, delete.
/// User preferences live in [SettingsProvider].
class ForecastProvider extends ChangeNotifier {
  final NominatimService _nominatimService;
  final CacheService _cacheService;
  final LocationRefresher _refresher;
  final SharedPreferences? _prefs;

  SavedLocation? currentLocation;
  List<SavedLocation> savedLocations = [];
  bool isLoading = false;
  String? errorMessage;

  ForecastProvider({
    required NwsService nwsService,
    required NominatimService nominatimService,
    required CacheService cacheService,
    required UsnoService usnoService,
    required OpenUvService openUvService,
    SharedPreferences? prefs,
  })  : _nominatimService = nominatimService,
        _cacheService = cacheService,
        _refresher = LocationRefresher(
          nwsService: nwsService,
          usnoService: usnoService,
          openUvService: openUvService,
        ),
        _prefs = prefs;

  Future<void> init() async {
    savedLocations = _cacheService.loadAll();
    if (savedLocations.isNotEmpty) {
      _sortLocations();
      currentLocation = savedLocations.first;
    }
    notifyListeners();
  }

  void _sortLocations() {
    savedLocations.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastAccessed.compareTo(a.lastAccessed);
    });
  }

  /// Re-reads saved locations from disk. The nightly sync runs in its own
  /// isolate and writes straight to SharedPreferences, so an app left open in
  /// the background would otherwise keep showing (and later re-save over)
  /// its stale in-memory copy.
  Future<void> reloadFromDisk() async {
    if (isLoading) return;
    await _prefs?.reload();
    final currentName = currentLocation?.displayName;
    savedLocations = _cacheService.loadAll();
    _sortLocations();
    currentLocation = savedLocations
            .where((l) => l.displayName == currentName)
            .firstOrNull ??
        savedLocations.firstOrNull;
    notifyListeners();
  }

  Future<List<SuggestionResult>> getSuggestions(String query) =>
      _nominatimService.suggest(query);

  Future<void> selectSuggestion(SuggestionResult s) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _fetchAndSave(s.displayName, s.lat, s.lon);
    } catch (e) {
      errorMessage = 'Error: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> searchLocation(String query) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final geo = await _nominatimService.search(query);
      if (geo == null) {
        errorMessage = 'Location not found';
        return;
      }
      await _fetchAndSave(geo.displayName, geo.lat, geo.lon, postcode: geo.postcode);
    } catch (e) {
      errorMessage = 'Error: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshCurrentLocation() async {
    if (currentLocation == null) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _fetchAndSave(
        currentLocation!.displayName,
        currentLocation!.lat,
        currentLocation!.lon,
        postcode: currentLocation!.postcode,
      );
    } on NwsUnsupportedLocationException catch (e) {
      errorMessage = e.toString();
    } catch (e) {
      errorMessage = 'Forecast unavailable, showing cached data';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchAndSave(
      String displayName, double lat, double lon, {String? postcode}) async {
    final location = await _refresher.refresh(
      displayName: displayName,
      lat: lat,
      lon: lon,
      cached: savedLocations
          .where((l) => l.displayName == displayName)
          .firstOrNull,
      postcode: postcode,
    );

    savedLocations = _cacheService.addOrUpdate(savedLocations, location);
    _sortLocations();
    _cacheService.saveAll(savedLocations);
    currentLocation = location;
  }

  Future<void> refreshPinnedLocations() async {
    final pinned = savedLocations.where((l) => l.isPinned).toList();
    if (pinned.isEmpty) return;

    final originalCurrentDisplayName = currentLocation?.displayName;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    var anyFailed = false;
    for (final loc in pinned) {
      try {
        await _fetchAndSave(loc.displayName, loc.lat, loc.lon,
            postcode: loc.postcode);
      } catch (_) {
        anyFailed = true;
      }
    }

    // _fetchAndSave reassigns currentLocation on every call; restore
    // whichever location was actually open before this refresh.
    if (originalCurrentDisplayName != null) {
      currentLocation = savedLocations
              .where((l) => l.displayName == originalCurrentDisplayName)
              .firstOrNull ??
          currentLocation;
    }

    errorMessage = anyFailed ? 'Some locations failed to refresh, showing cached data' : null;
    isLoading = false;
    notifyListeners();
  }

  void selectLocation(SavedLocation location) {
    currentLocation = location.copyWith(lastAccessed: DateTime.now());
    savedLocations =
        _cacheService.addOrUpdate(savedLocations, currentLocation!);
    _sortLocations();
    _cacheService.saveAll(savedLocations);
    notifyListeners();
  }

  void pinLocation(String displayName) {
    savedLocations = savedLocations.map((l) {
      if (l.displayName != displayName) return l;
      return l.copyWith(isPinned: !l.isPinned);
    }).toList();
    _sortLocations();
    _cacheService.saveAll(savedLocations);
    notifyListeners();
  }

  void deleteLocation(String displayName) {
    savedLocations =
        savedLocations.where((l) => l.displayName != displayName).toList();
    if (currentLocation?.displayName == displayName) {
      currentLocation = savedLocations.firstOrNull;
    }
    _cacheService.saveAll(savedLocations);
    notifyListeners();
  }

  /// Undoes [deleteLocation]. [wasCurrent] reopens it if it was the one
  /// on screen.
  void restoreLocation(SavedLocation location, {required bool wasCurrent}) {
    savedLocations = _cacheService.addOrUpdate(savedLocations, location);
    _sortLocations();
    if (wasCurrent || currentLocation == null) currentLocation = location;
    _cacheService.saveAll(savedLocations);
    notifyListeners();
  }
}
