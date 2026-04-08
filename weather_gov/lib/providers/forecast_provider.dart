import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../models/saved_location.dart';
import '../services/nominatim_service.dart';
import '../services/nws_service.dart';
import '../services/cache_service.dart';
import '../services/usno_service.dart';

class ForecastProvider extends ChangeNotifier {
  final NwsService _nwsService;
  final NominatimService _nominatimService;
  final CacheService _cacheService;
  final UsnoService _usnoService;
  final SharedPreferences? _prefs;

  SavedLocation? currentLocation;
  List<SavedLocation> savedLocations = [];
  Map<String, bool> visibleRows = Map.from(kDefaultRowVisibility);
  bool isDarkMode = false;
  bool isLoading = false;
  String? errorMessage;

  ForecastProvider({
    required NwsService nwsService,
    required NominatimService nominatimService,
    required CacheService cacheService,
    required UsnoService usnoService,
    SharedPreferences? prefs,
  })  : _nwsService = nwsService,
        _nominatimService = nominatimService,
        _cacheService = cacheService,
        _usnoService = usnoService,
        _prefs = prefs;

  Future<void> init() async {
    savedLocations = _cacheService.loadAll();
    if (savedLocations.isNotEmpty) {
      savedLocations.sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
      currentLocation = savedLocations.first;
    }
    _loadPreferences();
    notifyListeners();
  }

  void _loadPreferences() {
    if (_prefs == null) return;
    isDarkMode = _prefs.getBool('isDarkMode') ?? false;
    for (final row in kAllRows) {
      final saved = _prefs.getBool('row_$row');
      if (saved != null) visibleRows[row] = saved;
    }
  }

  void _savePreferences() {
    if (_prefs == null) return;
    _prefs.setBool('isDarkMode', isDarkMode);
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
      await _fetchAndSave(geo.displayName, geo.lat, geo.lon);
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
      String displayName, double lat, double lon) async {
    final result = await _nwsService.fetchForecast(lat, lon);
    final now = DateTime.now();

    final windowStart = result.periods.first.startTime.toLocal();
    final windowEnd   = result.periods.last.startTime.toLocal();
    final tzOffset    = now.timeZoneOffset.inHours;

    final astroDays = await _usnoService.fetchAstroData(
      lat: lat,
      lon: lon,
      windowStart: windowStart,
      windowEnd: windowEnd,
      tzOffsetHours: tzOffset,
    );

    final location = SavedLocation(
      displayName: result.locationName,
      lat: lat,
      lon: lon,
      lastAccessed: now,
      cachedForecast: result.periods,
      cachedAlerts: result.alerts,
      cacheTimestamp: now,
      cachedAstroData: astroDays,
    );

    savedLocations = _cacheService.addOrUpdate(savedLocations, location);
    _cacheService.saveAll(savedLocations);
    currentLocation = location;
  }

  void selectLocation(SavedLocation location) {
    currentLocation = location.copyWith(lastAccessed: DateTime.now());
    savedLocations =
        _cacheService.addOrUpdate(savedLocations, currentLocation!);
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
}
