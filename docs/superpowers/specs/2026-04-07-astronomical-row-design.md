# Astronomical Row — Design Spec
**Date:** 2026-04-07  
**Status:** Approved

---

## Overview

Add an "Astronomical" toggle to the app drawer that reveals a new combined row beneath the Conditions row. The row shows solar and lunar visibility for the entire forecast window using colored horizontal bands aligned to the existing hour grid.

---

## Layout

A single fixed-height row of **50dp**, split into two horizontal bands:

| Band | Height | Content |
|------|--------|---------|
| Sun | top 25dp | Solar segments + noon marker |
| Moon | bottom 25dp | Lunar arc |

The row uses `CustomPainter` (same pattern as `WindBarbRow`) inside a `SizedBox(width: periods.length * kPixelsPerHour, height: 50)`.

---

## Color Scheme

### Sun Band
| Segment | Color | Hex |
|---------|-------|-----|
| Night (before civil twilight / after end civil twilight) | `#0D0A1B` | |
| Civil Twilight (before sunrise / after sunset) | `#2A2347` | |
| Day (sunrise → sunset) | `#ECE557` | |
| High Noon marker (Upper Transit) | `#ED7B58` | 3px vertical bar, full 25dp height |

### Moon Band
| Segment | Color | Hex |
|---------|-------|-----|
| Moon below horizon | `#0D0A1B` | |
| Moon above horizon | `#B7C3C9` | |

### Failed/Missing Day
Diagonal hatching alternating `#0D0A1B` and `#2A2347` at ~45°, covering the full 50dp height for any day whose API call failed.

---

## Data Source

**API:** USNO Solar and Lunar Data (`rstt/oneday`)  
**Endpoint:** `https://aa.usno.navy.mil/api/rstt/oneday?date=YYYY-MM-DD&coords=LAT,LON&tz=TZ_OFFSET`  
**Calls:** One per calendar day in the forecast window (max 7), fired in parallel.

### Response fields used

**`sundata`:**
- `"Begin Civil Twilight"` → `beginCivilTwilight`
- `"Rise"` → `sunrise`
- `"Upper Transit"` → `solarNoon`
- `"Set"` → `sunset`
- `"End Civil Twilight"` → `endCivilTwilight`

**`moondata`:**
- `"Rise"` → `moonrise`
- `"Set"` → `moonset`

---

## Data Model

### `AstroDay`
```dart
class AstroDay {
  final DateTime date;           // midnight local time for this calendar day
  final DateTime? beginCivilTwilight;
  final DateTime? sunrise;
  final DateTime? solarNoon;
  final DateTime? sunset;
  final DateTime? endCivilTwilight;
  final DateTime? moonrise;
  final DateTime? moonset;
}
```

All `DateTime` fields are in local time. Missing events (polar days, circumpolar moon) are `null`.

### `SavedLocation` changes
Add `List<AstroDay> cachedAstroData` field. Serialized as JSON alongside `cachedForecast`. Follows the same cache lifetime — refreshes when weather refreshes.

---

## Service: `UsnoService`

```dart
class UsnoService {
  Future<List<AstroDay>> fetchAstroData({
    required double lat,
    required double lon,
    required DateTime windowStart,  // first period startTime
    required DateTime windowEnd,    // last period startTime
    required int tzOffsetHours,
  });
}
```

- Computes the set of calendar dates in `[windowStart, windowEnd]`
- Fires one HTTP GET per date in parallel (`Future.wait`)
- On HTTP error or parse failure for a date: returns a sentinel `AstroDay` with all fields null (painter draws hatching for that day)
- Times from API (`"06:43"`) are parsed as local time on that calendar date

---

## Provider Changes (`ForecastProvider`)

- `fetchAstroData()` called in parallel with the NWS weather fetch (via `Future.wait`)
- Result stored on `SavedLocation.cachedAstroData`
- Existing `visibleRows` map gains `kRowAstro` defaulting to `false`

---

## UI: `AstroRow` Widget

```dart
class AstroRow extends StatelessWidget {
  final List<HourlyPeriod> periods;  // for window start/length reference
  final List<AstroDay> astroDays;
  final double height;               // default 50.0
}
```

Delegates to `_AstroPainter extends CustomPainter`.

### Painter logic

**X-coordinate mapping:**  
`x = (localDateTime.difference(windowStart).inMinutes / 60.0) * kPixelsPerHour`

**Sun band (y: 0–25):**
1. Fill full width with night color `#0D0A1B`
2. For each `AstroDay`, paint segments in order:
   - `[beginCivilTwilight, sunrise)` → `#2A2347`
   - `[sunrise, sunset)` → `#ECE557`
   - `[sunset, endCivilTwilight)` → `#2A2347`
3. Paint noon marker: 3px rect at `solarNoon.x`, height 25dp, color `#ED7B58`
4. If `AstroDay` is a failure sentinel: skip steps 2–3, paint hatching for that day's 24 columns instead

**Moon band (y: 25–50):**
1. Fill full width with night color `#0D0A1B`
2. For each pair of consecutive `AstroDay` entries, stitch moon arcs:
   - If `moonrise` exists and `moonset` exists on the same day: paint `[moonrise, moonset)` → `#B7C3C9`
   - If `moonset < moonrise` (set before rise on the same day): moon rose the previous day — look back to prior `AstroDay.moonrise` to complete the arc across midnight
   - If only `moonrise` exists (sets next day): paint `[moonrise, end_of_day)` → `#B7C3C9`; continued by next day's `[start_of_day, moonset)` segment
3. No-moon days (both null): bar remains night color — no special treatment

**Failure hatching:**  
For a failed `AstroDay`, draw diagonal lines (45°, spacing 6px) alternating `#0D0A1B` and `#2A2347` across the full 50dp height for columns `[dayStart, dayStart + 24 * kPixelsPerHour)`.

---

## Constants (additions to `constants.dart`)

```dart
const String kRowAstro = 'Astronomical';

const Color kColorAstroNight        = Color(0xFF0D0A1B);
const Color kColorAstroCivilTwilight = Color(0xFF2A2347);
const Color kColorAstroDay          = Color(0xFFECE557);
const Color kColorAstroNoon         = Color(0xFFED7B58);
const Color kColorAstroMoonUp       = Color(0xFFB7C3C9);
```

`kRowAstro` added to `kAllRows` and `kDefaultRowVisibility` (default `false`).

---

## Edge Cases

| Case | Handling |
|------|---------|
| No sunrise (polar night) | `sunrise` and `sunset` null → entire sun band stays night color |
| No moonrise for a day | Both null → moon band stays night color for that day |
| Moon arc crosses midnight | Stitched using adjacent `AstroDay` moonrise/moonset |
| Partial first/last day | Painter clips naturally — `SizedBox` width = `periods.length * kPixelsPerHour` |
| API call fails | Sentinel `AstroDay` (all null) → diagonal hatching for that day |
| Timezone | UTC offset passed as `tz` param; all returned times are local |

---

## Files Affected

| File | Change |
|------|--------|
| `lib/constants.dart` | Add `kRowAstro` + 5 color constants |
| `lib/models/hourly_period.dart` | No change |
| `lib/models/astro_day.dart` | **New** — `AstroDay` model + JSON serialization |
| `lib/models/saved_location.dart` | Add `cachedAstroData` field |
| `lib/services/usno_service.dart` | **New** — USNO API client |
| `lib/providers/forecast_provider.dart` | Fetch + store astro data in parallel with NWS |
| `lib/ui/chart_rows/astro_row.dart` | **New** — `AstroRow` widget + `_AstroPainter` |
| `lib/ui/scrollable_chart.dart` | Add `kRowAstro` branch in `_buildRows` |
| `lib/ui/app_drawer.dart` | Add Astronomical toggle |
