import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../models/hourly_period.dart';
import '../models/saved_location.dart';
import '../services/nominatim_service.dart';
import '../services/nws_service.dart';
import '../services/cache_service.dart';
import '../services/usno_service.dart';
import '../services/openuv_service.dart';

class ForecastProvider extends ChangeNotifier {
  final NwsService _nwsService;
  final NominatimService _nominatimService;
  final CacheService _cacheService;
  final UsnoService _usnoService;
  final OpenUvService _openUvService;
  final SharedPreferences? _prefs;

  SavedLocation? currentLocation;
  List<SavedLocation> savedLocations = [];
  Map<String, bool> visibleRows = Map.from(kDefaultRowVisibility);
  bool isDarkMode = false;
  bool syncPinnedOnOpen = false;
  bool isLoading = false;
  String? errorMessage;

  ForecastProvider({
    required NwsService nwsService,
    required NominatimService nominatimService,
    required CacheService cacheService,
    required UsnoService usnoService,
    required OpenUvService epaUvService,
    SharedPreferences? prefs,
  })  : _nwsService = nwsService,
        _nominatimService = nominatimService,
        _cacheService = cacheService,
        _usnoService = usnoService,
        _openUvService = epaUvService,
        _prefs = prefs;

  Future<void> init() async {
    savedLocations = _cacheService.loadAll();
    if (savedLocations.isNotEmpty) {
      _sortLocations();
      currentLocation = savedLocations.first;
    }
    _loadPreferences();
    notifyListeners();
    if (syncPinnedOnOpen) _syncPinned();
  }

  void _sortLocations() {
    savedLocations.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastAccessed.compareTo(a.lastAccessed);
    });
  }

  Future<void> _syncPinned() async {
    final now = DateTime.now();
    final stale = savedLocations
        .where((l) => l.isPinned && now.difference(l.cacheTimestamp).inMinutes >= 60)
        .toList();
    if (stale.isEmpty) return;
    // Current location first (if in the stale list), then the rest.
    final current = currentLocation;
    final ordered = [
      if (current != null && stale.any((l) => l.displayName == current.displayName)) current,
      ...stale.where((l) => l.displayName != current?.displayName),
    ];
    isLoading = true;
    notifyListeners();
    for (final loc in ordered) {
      try {
        await _fetchAndSave(loc.displayName, loc.lat, loc.lon, postcode: loc.postcode);
      } catch (_) {}
    }
    isLoading = false;
    notifyListeners();
  }

  void _loadPreferences() {
    if (_prefs == null) return;
    isDarkMode = _prefs.getBool('isDarkMode') ?? false;
    syncPinnedOnOpen = _prefs.getBool('syncPinnedOnOpen') ?? false;
    for (final row in kAllRows) {
      final saved = _prefs.getBool('row_$row');
      if (saved != null) visibleRows[row] = saved;
    }
  }

  void _savePreferences() {
    if (_prefs == null) return;
    _prefs.setBool('isDarkMode', isDarkMode);
    _prefs.setBool('syncPinnedOnOpen', syncPinnedOnOpen);
    for (final entry in visibleRows.entries) {
      _prefs.setBool('row_${entry.key}', entry.value);
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
    final now = DateTime.now();

    // Fetch NWS and astro data (USNO needs tzOffset so it runs after NWS).
    final result = await _nwsService.fetchForecast(lat, lon);
    final rawAstroDays = await _usnoService.fetchAstroData(
      lat: lat,
      lon: lon,
      windowStart: now,
      windowEnd: now.add(const Duration(days: 7)),
      tzOffsetHours: result.tzOffsetHours,
    );

    // Build existing UV map from cached astro data.
    final cachedLocation = savedLocations
        .where((l) => l.displayName == result.locationName)
        .firstOrNull;
    final existingUv = <String, int>{};
    if (cachedLocation != null) {
      for (final d in cachedLocation.cachedAstroData) {
        if (d.uvIndex != null) {
          final k = '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}';
          existingUv[k] = d.uvIndex!;
        }
      }
    }

    // Fetch UV — only missing days + today.
    final uvMap = await _openUvService.fetchUvForWindow(
      lat: lat,
      lon: lon,
      existing: existingUv,
      windowStart: now,
    );

    final astroDays = rawAstroDays.map((d) {
      final key =
          '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}';
      final uv = uvMap[key];
      return uv != null ? d.copyWith(uvIndex: uv) : d;
    }).toList();

    // Prepend cached periods from the past 24 hours that predate the new fetch.
    final lookback = now.subtract(const Duration(hours: 24));
    final newStart = result.periods.isNotEmpty
        ? result.periods.first.startTime
        : now;
    final yesterdayPeriods = cachedLocation != null
        ? cachedLocation.cachedForecast
            .where((p) =>
                !p.startTime.isBefore(lookback) &&
                p.startTime.isBefore(newStart))
            .toList()
        : <HourlyPeriod>[];
    final mergedPeriods = [...yesterdayPeriods, ...result.periods];

    final location = SavedLocation(
      displayName: result.locationName,
      lat: lat,
      lon: lon,
      lastAccessed: now,
      cachedForecast: mergedPeriods,
      cachedAlerts: result.alerts,
      cacheTimestamp: now,
      cachedAstroData: astroDays,
      isPinned: cachedLocation?.isPinned ?? false,
      postcode: postcode ?? cachedLocation?.postcode,
    );

    savedLocations = _cacheService.addOrUpdate(savedLocations, location);
    _sortLocations();
    _cacheService.saveAll(savedLocations);
    currentLocation = location;
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

  void toggleSyncPinnedOnOpen() {
    syncPinnedOnOpen = !syncPinnedOnOpen;
    _savePreferences();
    notifyListeners();
  }
}
