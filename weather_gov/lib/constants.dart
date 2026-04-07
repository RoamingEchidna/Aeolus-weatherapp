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
const Color kColorHumidity    = Color(0xFF006600);
const Color kColorPrecip      = Color(0xFF996633);
const Color kColorSkycover    = Color(0xFF0000CC);
const Color kColorWind        = Color(0xFF990099); // wind barb color

// Weather type colors (Conditions row)
const Color kColorWeatherRain         = Color(0xFF009900);
const Color kColorWeatherThunder      = Color(0xFFFF0000);
const Color kColorWeatherSnow         = Color(0xFF0099CC);
const Color kColorWeatherFreezingRain = Color(0xFFCC99CC);
const Color kColorWeatherSleet        = Color(0xFFF06600);

// Alert severity colors
const Color kColorAlertExtreme  = Color(0xFFD32F2F);
const Color kColorAlertSevere   = Color(0xFFD32F2F);
const Color kColorAlertModerate = Color(0xFFF57C00);
const Color kColorAlertMinor    = Color(0xFFF9A825);

// Row group names
const String kRowTempGroup   = 'Temp & Dew';
const String kRowWindGroup   = 'Wind';
const String kRowAtmosGroup  = 'RH / Precip';
const String kRowConditions  = 'Conditions';

const List<String> kAllRows = [
  kRowTempGroup,
  kRowWindGroup,
  kRowAtmosGroup,
  kRowConditions,
];

const Map<String, bool> kDefaultRowVisibility = {
  kRowTempGroup:  true,
  kRowWindGroup:  true,
  kRowAtmosGroup: true,
  kRowConditions: true,
};
