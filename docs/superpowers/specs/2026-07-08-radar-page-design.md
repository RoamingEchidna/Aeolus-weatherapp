# Radar Page — Design Spec

**Date:** 2026-07-08
**Status:** Draft — pending user review

## Goal

Add a radar view to Aeolus: a button in the top app bar (next to the local
time) opens a secondary page showing an animated reflectivity loop for the
currently selected location, drawn over state/county boundaries with a dot
marking the location. Frames are fetched live from NOAA's WMS services and
cached on disk so previously fetched frames survive app restarts, building up
to a 5-hour rolling history.

## Background: data sources (verified 2026-07-08)

`api.weather.gov`'s `/radar/*` endpoints expose **station metadata only** — no
imagery. Imagery comes from NOAA's GeoServer WMS:

| Purpose | Endpoint |
|---|---|
| Station list (for nearest-station lookup) | `https://api.weather.gov/radar/stations` (GeoJSON; `geometry.coordinates` = [lon, lat]) |
| Per-station reflectivity | `https://opengeo.ncep.noaa.gov/geoserver/{station}/ows` — layer `{station}_sr_bref` (Super Resolution Base Reflectivity), e.g. `kabr_sr_bref` |
| CONUS composite (fallback) | `https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows` — layer `conus_bref_qcd` |
| State + county boundaries | `https://mapservices.weather.noaa.gov/static/services/nws_reference_maps/nws_reference_map/MapServer/WMSServer` — WMS layer names `8` (states), `9` (counties) |

Key facts confirmed against the live services:

- Radar layers expose an OGC `TIME` dimension. `GetCapabilities` lists every
  available timestamp: a rolling window of roughly **the last 2 hours at
  ~5–7 minute intervals** (~18 frames). No forecast radar exists; NOAA radar
  is observational only.
- All layers support `CRS:84` (lon/lat axis order). Use `CRS:84`, not
  `EPSG:4326`, to avoid WMS 1.3.0's swapped axis order.
- Radar and boundary layers return transparent-background PNGs, so images
  requested with identical bbox/width/height stack cleanly without any
  pixel-level compositing.
- All requests send the app's existing `User-Agent: WeatherGovApp/1.0` header.

## Architecture

Three new units, following the existing service/screen split:

### 1. `RadarService` (`lib/services/radar_service.dart`)

Stateless HTTP wrapper, constructor-injected `http.Client` like `NwsService`.

- `Future<RadarSource> resolveSource(double lat, double lon)` — fetches the
  station list, finds the nearest station by haversine distance.
  - If the nearest station is **≤ 200 km** away → `RadarSource.station(id)`.
  - If it is farther, or the lookup fails (network error, empty list) →
    `RadarSource.composite()` (CONUS mosaic). 200 km ≈ NEXRAD's useful
    low-tilt range; beyond it the station image would be mostly blank.
- `Future<List<DateTime>> fetchAvailableTimes(RadarSource source)` — issues
  `GetCapabilities`, parses the `<Dimension name="time">` extent for the
  reflectivity layer into a timestamp list.
- `Future<Uint8List> fetchFrame(RadarSource source, LatLonBox bbox, DateTime time)` —
  one `GetMap` with `time=` parameter; returns PNG bytes.
- `Future<Uint8List> fetchBoundaries(LatLonBox bbox)` — one `GetMap` against
  the reference-map WMS with `layers=8,9` (states + counties in a single
  call), `transparent=true`.

GetMap parameters common to all image requests:
`service=WMS&version=1.3.0&request=GetMap&crs=CRS:84&bbox={w},{s},{e},{n}&width=800&height=800&format=image/png&transparent=true`.

The bbox is **±2° around the selected location** (~440 km × ~340 km at CONUS
latitudes), centered on the location — not the station — so the view is local.
Square pixel dimensions with a square degree box means modest lat/lon aspect
distortion; acceptable for v1 (the official RIDGE viewer has the same
property at fixed zoom).

### 2. `RadarFrameCache` (`lib/services/radar_frame_cache.dart`)

Disk-backed frame cache in the app's cache directory (via the
`path_provider` package — **new dependency**).

- File naming: `radar_{sourceKey}_{lat}_{lon}_{timestampMillis}.png` where
  `sourceKey` is the station id or `conus`, and lat/lon are rounded to 2
  decimals. Encoding the location in the key means switching locations never
  serves a stale bbox; old locations' frames simply age out.
- Boundary image cached the same way (`bounds_{lat}_{lon}.png`) with **no
  expiry** — boundaries don't change. Never re-fetched once present for a
  given location.
- `Future<Map<DateTime, Uint8List>> loadFrames(sourceKey, lat, lon)` — reads
  all cached frames for this source+location.
- `Future<void> saveFrame(...)`, `Future<Uint8List?> loadBoundaries(...)`,
  `Future<void> saveBoundaries(...)`.
- **Eviction:** on every page open and every refresh, delete cached frame
  files older than `now − 5 hours` (all sources/locations, cheap directory
  scan). The WMS only serves ~2 hours back, so the cache is what extends
  history: visiting at 3 PM and again at 5 PM accumulates a 1 PM–5 PM loop.
  Frames between visits that rolled out of NOAA's window before being
  fetched are permanently missed — accepted limitation, noted in UI simply
  by the timestamp gaps being invisible (loop just steps through what exists).

### 3. `RadarScreen` (`lib/ui/radar_screen.dart`)

Pushed via `Navigator.push`; receives the `SavedLocation`. Owns all playback
state. No provider changes needed beyond none at all — the screen talks to
`RadarService`/`RadarFrameCache` directly (matches how `AppDrawer` uses
`url_launcher` directly rather than routing everything through the provider).

**Load sequence:**

1. Evict stale cache, then load cached frames + boundaries for this location
   → if any exist, display immediately (instant paint from disk).
2. `resolveSource()` → `fetchAvailableTimes()` → fetch only timestamps not
   already cached → save each to cache as it arrives, updating the loop
   progressively.
3. Fetch boundaries only on cache miss.

**Display:** a `Stack` of three children sized identically:
boundary PNG (bottom), current radar frame PNG (top), and a small filled
circle marker positioned by linear interpolation of the location's lon/lat
within the bbox. Below the image: playback controls and the current frame's
timestamp (formatted with the app's existing 12/24-hour preference).

**Playback controls:**

- **Play/pause** toggle. Auto-plays on open, looping oldest → newest.
- **Scrub slider** (`Slider`, divisions = frameCount − 1). Dragging pauses
  playback and shows the selected frame; timestamp label tracks the thumb.
- **Speed button** cycling three settings: `0.5×` (800 ms/frame),
  `1×` (400 ms/frame), `2×` (200 ms/frame). Label shows the current setting.
- **Refresh** icon in the radar page app bar: re-runs
  `fetchAvailableTimes()`, fetches only new timestamps, evicts >5 h frames.
  Never re-fetches boundaries or already-cached frames.

**App bar entry point** (`chart_screen.dart`): an `IconButton`
(`Icons.radar`) added to the `AppBar.actions`, sitting immediately right of
the local-time text. Disabled when `currentLocation == null`.

## Error handling

| Failure | Behavior |
|---|---|
| Station lookup fails / nearest > 200 km | Fall back to CONUS composite source (transparent to the user apart from coarser imagery). |
| `GetCapabilities` fails and cache is empty | Full-page error state with Retry button. |
| `GetCapabilities` fails but cached frames exist | Show cached loop + a snackbar/banner: "Couldn't fetch latest radar, showing cached frames". |
| Individual frame `GetMap` fails | Skip that frame; loop plays what it has. |
| Boundary fetch fails | Show radar without boundaries (still usable), retry on next visit. |
| Location outside all coverage (e.g. international) | Composite fallback returns an empty/blank image; acceptable — NWS-unsupported locations already fail earlier in the app at forecast fetch. |

## Non-goals (this version)

- **No forecast/nowcast radar** — doesn't exist from NOAA; would require
  third-party extrapolation.
- **History beyond 5 h** — would require the MRMS GRIB2 archive on AWS and a
  full decode/render pipeline.
- **No pan/zoom or map library** — fixed bbox; `flutter_map` is the v2 path
  if interactivity is wanted.
- **No radar in background sync** — frames are fetched only on the radar
  page, never by the nightly job.
- Velocity/precip-type products (`_sr_bvel`, `_bdsa`, …) — reflectivity only.

## Testing

- Unit-test `RadarService` URL construction and capabilities-XML timestamp
  parsing with a mocked `http.Client` (same pattern as existing service
  tests, if any; otherwise these become the first).
- Unit-test nearest-station selection + 200 km fallback threshold with a
  canned station list.
- Unit-test `RadarFrameCache` eviction (frames straddling the 5 h boundary)
  using a temp directory.
- Manual on-device pass: open radar for a pinned location near a NEXRAD site
  (station path) and a location > 200 km from any site (composite path);
  verify loop, scrub, speed cycling, refresh-only-fetches-new, and
  cross-session cache persistence.

## New dependencies

- `path_provider` — app cache directory for the frame cache. Well-maintained
  first-party Flutter plugin; no manifest changes needed.

## Implementation notes (read before writing code)

Concrete gotchas verified against the live services; deviating from these
will produce hard-to-debug blank images or 400s.

1. **TIME values must be echoed verbatim.** GeoServer lists timestamps like
   `2026-07-08T16:13:01.000Z` in the capabilities `<Dimension name="time">`
   extent. Pass that exact string as the `time=` GetMap parameter. Do NOT
   round-trip through `DateTime.parse(...).toIso8601String()` — Dart drops
   or reformats the milliseconds and GeoServer may return an empty image for
   a non-matching time. Keep the original string as the canonical frame key;
   parse to `DateTime` only for sorting, display, and eviction math. In cache
   filenames, encode the string's `millisecondsSinceEpoch` (colons are not
   filename-safe).

2. **Axis order.** Use `crs=CRS:84` everywhere so bbox is
   `minLon,minLat,maxLon,maxLat`. Do not use `EPSG:4326` with WMS 1.3.0 —
   it swaps to lat-first and silently returns a wrong/blank crop.

3. **Station id casing.** `api.weather.gov` returns `KABR`; the GeoServer
   workspace and layer are lowercase: `.../geoserver/kabr/ows`,
   `layers=kabr_sr_bref`.

4. **Filter stations to `stationType == "WSR-88D"`.** The list also contains
   TDWR sites whose layer naming/products differ.

5. **Fallback chain:** nearest WSR-88D > 200 km OR station-list fetch fails
   OR the station's own GetCapabilities fails → composite
   (`.../geoserver/conus/conus_bref_qcd/ows`, `layers=conus_bref_qcd`, same
   TIME handling). Cache the resolved source per rounded lat/lon in
   `SharedPreferences` (`radarSource_{lat}_{lon}` → station id or `conus`)
   so the ~large station-list download doesn't repeat every page open.

6. **Always send `styles=` (empty) in GetMap** — the parameter is mandatory
   in WMS even when empty, and the ArcGIS boundary server is stricter than
   GeoServer. For the two-layer boundary call use `layers=8,9&styles=,`.

7. **Sample requests** (bbox for lat 37.36, lon −118.40, ±2°):
   - Frame:
     `https://opengeo.ncep.noaa.gov/geoserver/kesx/ows?service=WMS&version=1.3.0&request=GetMap&layers=kesx_sr_bref&styles=&crs=CRS:84&bbox=-120.40,35.36,-116.40,39.36&width=800&height=800&format=image/png&transparent=true&time=2026-07-08T18:04:04.000Z`
   - Boundaries:
     `https://mapservices.weather.noaa.gov/static/services/nws_reference_maps/nws_reference_map/MapServer/WMSServer?service=WMS&version=1.3.0&request=GetMap&layers=8,9&styles=,&crs=CRS:84&bbox=-120.40,35.36,-116.40,39.36&width=800&height=800&format=image/png&transparent=true`
   - Send `User-Agent: WeatherGovApp/1.0` on every request (existing app
     convention; NOAA asks for an identifying UA).

8. **Capabilities parsing:** extract the time extent with a targeted regex /
   string scan for the `{layer}` block's `<Dimension name="time">…</Dimension>`
   content (comma-separated list). Do not add an XML-parsing dependency for
   this.

9. **Flicker-free playback:** render frames with
   `Image.memory(bytes, gaplessPlayback: true)` — without `gaplessPlayback`
   every frame swap flashes white. Drive playback with a `Timer.periodic`
   held in the screen state; cancel and recreate it on speed change; cancel
   in `dispose()`.

10. **Fetch order:** fetch the newest missing frame first and display it
    immediately as a static image, then backfill older frames; start the
    loop when backfilling completes. The user sees current conditions in
    one round-trip instead of waiting for ~18 fetches.

11. **Dark mode:** boundary strokes from the NOAA server are dark; give the
    map `Stack` a fixed light neutral background (e.g. `Colors.grey.shade300`)
    in both themes rather than the theme surface color, or lines vanish in
    dark mode.

12. **Marker math:** with the image rendered in a square `AspectRatio(1)` /
    `LayoutBuilder`, the dot position is
    `dx = (lon − minLon) / (maxLon − minLon) * renderWidth`,
    `dy = (maxLat − lat) / (maxLat − minLat) * renderHeight` (y inverted).

13. **Scope discipline:** no changes to `ForecastProvider` state, background
    worker, or sync logic. New files only, plus the one `IconButton` added to
    `chart_screen.dart`'s AppBar `actions`. Run
    `flutter analyze` on all touched files before claiming completion.
