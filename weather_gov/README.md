# Weather Gov

An Android app that displays a scrollable hourly forecast chart using data from the
[National Weather Service API](https://www.weather.gov/documentation/services-web-api).
Search any US location by name, then scroll through up to 156 hours (6.5 days) of:

- **Temperature, Wind Chill & Dewpoint** — overlapping line chart
- **Wind** — meteorological wind barbs (speed + direction)
- **Humidity, Precipitation Potential & Sky Cover** — overlapping line chart
- **Conditions** — grouped forecast text with tap-to-read overlay

Saved locations are cached locally (up to 10) so recent forecasts load instantly.

---

## Tools Required

| Tool | Purpose | Download |
|------|---------|----------|
| **Flutter SDK** (≥ 3.22) | Build and run the app | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| **Android Studio** | Provides the Android SDK and ADB | [developer.android.com](https://developer.android.com/studio) |
| **ADB** (Android Debug Bridge) | Communicate with the device over USB | Included with Android Studio |
| **Java JDK** (≥ 17) | Required by the Android build toolchain | Bundled with Android Studio |

> **Windows note:** After installing Flutter, add the `flutter/bin` folder to your
> system `PATH`. Android Studio installs ADB at
> `%LOCALAPPDATA%\Android\Sdk\platform-tools\` — add that to `PATH` too.

---

## Running on an Android Device via USB

### 1. Enable USB Debugging on the Phone

1. Open **Settings → About phone**.
2. Tap **Build number** seven times until "You are now a developer" appears.
3. Go to **Settings → Developer options**.
4. Enable **USB debugging**.

### 2. Connect and Verify

Plug the phone into your PC with a USB data cable (not a charge-only cable).
Accept the "Allow USB debugging?" prompt on the phone.

```bash
adb devices
```

You should see your device listed with the status `device`. If it shows
`unauthorized`, unplug, re-plug, and accept the prompt again.

### 3. Install Dependencies

```bash
cd weather_gov
flutter pub get
```

### 4. Run

```bash
flutter run
```

Flutter will detect the connected device, build the app, and install it
automatically. The first build takes a few minutes; subsequent runs are faster.

Use these keys while the app is running:

| Key | Action |
|-----|--------|
| `r` | Hot reload (apply code changes instantly) |
| `R` | Hot restart (full restart, clears state) |
| `q` | Quit |

### 5. Build a Standalone APK (optional)

To install the app without a PC connection (sideload):

```bash
flutter build apk --release
```

The APK is output to `build/app/outputs/flutter-apk/app-release.apk`.
Transfer it to the phone and open it to install (requires **Install unknown apps**
enabled in Developer options).

---

## Project Structure

```
lib/
  main.dart                  # App entry point, theme, providers
  constants.dart             # Layout sizes, chart colors, row names
  models/
    hourly_period.dart       # NWS hourly period model + wind chill / sky cover
    saved_location.dart      # Cached location model
    weather_alert.dart       # NWS alert model
  providers/
    forecast_provider.dart   # State: current forecast, row visibility, dark mode
  services/
    nws_service.dart         # NWS API calls (points → hourly + alerts)
    nominatim_service.dart   # OpenStreetMap geocoding (no API key required)
    cache_service.dart       # SharedPreferences LRU cache (10 locations)
  ui/
    chart_screen.dart        # Main forecast screen
    scrollable_chart.dart    # Chart layout: scroll view + fixed overlays
    time_axis.dart           # Pinned hour/date tick row
    app_drawer.dart          # Side drawer: saved locations, row toggles
    chart_rows/
      multi_line_chart_row.dart  # Overlapping line charts (fl_chart)
      wind_barb_row.dart         # Meteorological wind barbs (CustomPainter)
      conditions_row.dart        # Grouped forecast text with tap overlay
```
