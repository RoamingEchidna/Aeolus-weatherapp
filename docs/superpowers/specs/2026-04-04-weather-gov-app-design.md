# Weather.gov Scrollable Forecast App — Design Spec

**Date:** 2026-04-04  
**Platform:** Android (Flutter), targeting Google Pixel 6 / Android 16  
**Distribution:** Sideloaded APK (`flutter build apk`)

---

## Overview

A Flutter Android app that fetches 7-day hourly forecast data from the NWS API and displays it as a horizontally scrollable, multi-row chart — replacing the "forward 2 days" pagination of the weather.gov graphical forecast page. Users can search for any location, toggle chart rows on/off, and view active weather alerts. Data is cached locally so the app works offline with the last fetched data.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  UI Layer                                   │
│  ┌──────────────────┐  ┌─────────────────┐  │
│  │  ChartScreen     │  │  Drawer (Menu)  │  │
│  │  - AppBar        │  │  - Search box   │  │
│  │  - AlertBanner   │  │  - Past locs    │  │
│  │  - ScrollChart   │  │  - Row toggles  │  │
│  └──────────────────┘  │  - Dark mode    │  │
│                         └─────────────────┘  │
├─────────────────────────────────────────────┤
│  State / Logic Layer                        │
│  ForecastProvider (ChangeNotifier)          │
│  - current location + forecast data         │
│  - active alerts                            │
│  - row visibility toggles                   │
│  - dark mode preference                     │
│  - offline/online state                     │
├─────────────────────────────────────────────┤
│  Services                                   │
│  NominatimService   NwsService   CacheService│
├─────────────────────────────────────────────┤
│  Models                                     │
│  HourlyPeriod   WeatherAlert   SavedLocation│
└─────────────────────────────────────────────┘
```

---

## Screens & UI

### App Bar (always pinned at top)
- Hamburger icon (☰) opens the drawer
- Location name displayed (e.g., "Bishop, CA")

### Alert Banner (below app bar, only visible when alerts exist)
- Color-coded by severity:
  - Extreme / Severe → Red
  - Moderate → Orange
  - Minor → Yellow
- Shows headline text (e.g., "FLOOD WATCH until 8pm Sat")
- Tapping expands a bottom sheet with full alert details (description, instruction, onset, expires)
- If multiple alerts, banner shows count and cycles or stacks them

### Scrollable Chart
- Fixed left column: row labels (pinned, does not scroll)
- Time axis at top: hour marks + day labels (e.g., "Sat", "6am", "12pm"), scrolls with chart
- All chart rows locked to the same horizontal scroll position
- Each visible row renders its chart using `fl_chart`

#### Chart Rows (all toggleable)

| Row | Chart Type | Color | Data Field |
|---|---|---|---|
| Temperature | Line chart | `#FF0000` (red) | `temperature` (°F) |
| Dewpoint | Line chart | `#00AA00` (green) | `dewpoint` (converted to °F) |
| Precip. Chance | Bar chart | `#4DA6FF` (light blue) | `probabilityOfPrecipitation` (%) |
| Humidity | Area chart | `#00CCCC` (teal) | `relativeHumidity` (%) |
| Wind Speed | Bar chart | `#0000CC` (dark blue) | `windSpeed` (mph, parsed from string; range averaged) |
| Wind Direction | Arrow icons | `#888888` (gray) | `windDirection` (cardinal string) |
| Conditions | Icon strip | NWS icon URLs | `icon` (URL, rendered as image) |

Chart colors remain constant in both light and dark mode. Only UI chrome (background, drawer, text) changes with the theme.

### Drawer (Slide-out Menu)

```
┌─────────────────────────┐
│ [Search box            ]│  ← single text input, Nominatim search
│ ▾ Past Locations        │  ← dropdown, up to 10 saved locations
│ [ Grab new data ]       │  ← button, fetches fresh data for current location
├─────────────────────────┤
│ ● Temperature      [on] │
│ ● Dewpoint        [off] │
│ ● Precip. Chance   [on] │
│ ● Humidity         [on] │
│ ● Wind Speed       [on] │
│ ● Wind Direction   [on] │
│ ● Conditions       [on] │
├─────────────────────────┤
│ ☀ / ☾  Dark Mode  [ ] │  ← Unicode sun/moon, toggle switch
└─────────────────────────┘
```

- Submitting the search box fetches data for the new location and closes the drawer
- Past Locations dropdown shows the last 10 searched locations by name; selecting one loads its cached data immediately
- "Grab new data" button fetches fresh forecast + alerts for the current location; disabled with a loading indicator while a fetch is in progress
- Row toggles are `Switch` widgets; state persists across app restarts
- Dark mode toggle persists across app restarts

---

## Data Layer

### NominatimService
- Endpoint: `https://nominatim.openstreetmap.org/search?q={query}&format=json&limit=1`
- Required header: `User-Agent: WeatherGovApp/1.0`
- Returns: display name, latitude, longitude
- On no results: shows a snackbar "Location not found"

### NwsService
1. `GET https://api.weather.gov/points/{lat},{lon}` → extracts `gridId`, `gridX`, `gridY`, `timeZone`, `forecastHourly` URL, and `relativeLocation` (city/state display name)
2. `GET {forecastHourly}` → list of `HourlyPeriod` objects (up to 156 hours / ~7 days)
3. `GET https://api.weather.gov/alerts/active?point={lat},{lon}` → list of `WeatherAlert` objects

All three requests fire in parallel (calls 2 and 3 after call 1 resolves).

### CacheService
- Storage: `shared_preferences` (simple, no extra setup)
- Stores up to 10 `SavedLocation` entries, each containing:
  - Display name, lat, lon
  - Cached `HourlyPeriod` list (JSON)
  - Cached `WeatherAlert` list (JSON)
  - Cache timestamp
- Eviction: when an 11th location is added, the oldest (by last-accessed time) is removed
- On load: most recently accessed location is loaded automatically

---

## Models

### HourlyPeriod
```dart
class HourlyPeriod {
  final DateTime startTime;
  final int temperature;           // °F
  final int precipChance;          // 0–100
  final int relativeHumidity;      // 0–100
  final double dewpointF;          // converted from °C
  final double windSpeedMph;       // parsed from "3 mph" or average of "10 to 15 mph" → 12.5
  final String windDirection;      // "N", "SSE", etc.
  final String shortForecast;
  final String iconUrl;
}
```

### WeatherAlert
```dart
class WeatherAlert {
  final String event;        // "Flood Watch", "Tornado Warning", etc.
  final String severity;     // "Extreme", "Severe", "Moderate", "Minor"
  final String headline;
  final String description;
  final String instruction;
  final DateTime onset;
  final DateTime expires;
}
```

### SavedLocation
```dart
class SavedLocation {
  final String displayName;
  final double lat;
  final double lon;
  final DateTime lastAccessed;
  final List<HourlyPeriod> cachedForecast;
  final List<WeatherAlert> cachedAlerts;
  final DateTime cacheTimestamp;
}
```

---

## Offline Behavior

- On launch: loads most recent cached location immediately, shows cached data
- Data is only fetched when the user explicitly requests it (search or "Grab new data")
- If offline when user requests data: shows a snack bar "No internet connection"
- If offline with cached data: shows "Showing cached data from [timestamp]" as a non-intrusive banner
- If no cached data exists yet: shows an empty state prompting the user to search for a location
- Network errors on fetch: show a snack bar, keep displaying cached data

---

## State Management

Single `ForecastProvider` using Flutter's `ChangeNotifier` + `Provider` package:
- `currentLocation`: active `SavedLocation`
- `savedLocations`: ordered list of up to 10 `SavedLocation`
- `visibleRows`: `Map<String, bool>` of row name → shown/hidden
- `isDarkMode`: bool
- `isLoading`: bool
- `isOffline`: bool
- `alerts`: `List<WeatherAlert>`

---

## Dependencies

| Package | Purpose |
|---|---|
| `provider` | State management |
| `fl_chart` | Chart rendering (line, bar, area) |
| `shared_preferences` | Local cache + settings persistence |
| `http` | API requests |
| `intl` | Date/time formatting |

All are well-maintained Flutter pub.dev packages. No Firebase, no accounts, no tracking.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Location not found (Nominatim) | Snack bar: "Location not found" |
| NWS API error (5xx) | Snack bar: "Forecast unavailable, showing cached data" |
| NWS grid not found (some offshore/border points) | Snack bar: "Location not supported by NWS" |
| No internet, no cache | Full-screen error with retry button |
| No internet, has cache | Load cache, show offline banner |
| Alert fetch fails | Silently suppress (alerts are non-critical) |

---

## Out of Scope

- Push notifications for alerts
- Widgets / home screen integration
- Multiple simultaneous location views
- Imperial/metric toggle (app uses °F / mph throughout, matching NWS API defaults)
- Tablet layout optimization
