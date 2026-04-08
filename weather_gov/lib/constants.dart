import 'package:flutter/material.dart';

// Layout
const double kPixelsPerHour = 24.0;
const double kChartRowHeight = 100.0;
const double kTimeAxisHeight = 32.0;
const double kLabelColumnWidth = 56.0;
const int kMaxSavedLocations = 10;

// Chart colors
const Color kColorTemperature = Color(0xFFFF0000);
const Color kColorWindChill   = Color(0xFF0000CC);
const Color kColorDewpoint    = Color(0xFF009900);
const Color kColorHumidity    = Color(0xFF178017);
const Color kColorPrecip      = Color(0xFF0000CC);
const Color kColorSkycover    = Color(0xFF1B66B0);
const Color kColorWind        = Color(0xFF990099); // wind barb color

// Weather type colors (Conditions row)
const Color kColorWeatherRain         = Color(0xFF009900);
const Color kColorWeatherThunder      = Color(0xFFFF0000);
const Color kColorWeatherSnow         = Color(0xFF0099CC);
const Color kColorWeatherFreezingRain = Color(0xFFCC99CC);
const Color kColorWeatherSleet        = Color(0xFFF06600);

// Theme palette — light mode
const Color kLightSurface                  = Color(0xFFF1F0E8);
const Color kLightSurfaceContainerHighest  = Color(0xFFE5E1DA);
const Color kLightPanelBackground          = Color(0xFFB3C8CF);
const Color kLightOutline                  = Color(0xFF89A8B2);
const Color kLightOnSurface                = Color(0xFF074F57);

// Theme palette — dark mode
const Color kDarkSurface                   = Color(0xFF2D2D2D);
const Color kDarkSurfaceContainerHighest   = Color(0xFF6A876A);
const Color kDarkPanelBackground           = Color(0xFF82AA82);
const Color kDarkOutline                   = Color(0xFF99CC99);
const Color kDarkOnSurface                 = Color(0xFFFED9B7);

// Cursor color
const Color kColorCursor = Color(0xFFFDD835);

// Alert severity colors
const Color kColorAlertExtreme  = Color(0xFFA91818);
const Color kColorAlertSevere   = Color(0xFFA91818);
const Color kColorAlertModerate = Color(0xFFF57C00);
const Color kColorAlertMinor    = Color(0xFFF9A825);

// Astronomical row colors
const Color kColorAstroNight          = Color(0xFF1A1725);
const Color kColorAstroCivilTwilight  = Color(0xFF443A6C);
const Color kColorAstroDay            = Color(0xFFECE557);
const Color kColorAstroNoon           = Color(0xFFE07A5F);
const Color kColorAstroMoonUp         = Color(0xFF92ACBA);

// Row group names
const String kRowTempGroup   = 'Temp & Dew';
const String kRowWindGroup   = 'Wind';
const String kRowAtmosGroup  = 'RH / Precip';
const String kRowConditions  = 'Conditions';
const String kRowAstro       = 'Astronomical';

const List<String> kAllRows = [
  kRowTempGroup,
  kRowWindGroup,
  kRowAtmosGroup,
  kRowConditions,
  kRowAstro,
];

const Map<String, bool> kDefaultRowVisibility = {
  kRowTempGroup:  true,
  kRowWindGroup:  true,
  kRowAtmosGroup: true,
  kRowConditions: true,
  kRowAstro:      false,
};
