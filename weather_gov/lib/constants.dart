import 'package:flutter/material.dart';

// Layout
const double kPixelsPerHour = 24.0;
const double kChartRowHeight = 80.0;
const double kTimeAxisHeight = 32.0;
const double kLabelColumnWidth = 84.0;
const int kMaxSavedLocations = 10;

// Chart colors (constant in light and dark mode)
const Color kColorTemperature   = Color(0xFFFF0000);
const Color kColorDewpoint      = Color(0xFF00AA00);
const Color kColorPrecip        = Color(0xFF4DA6FF);
const Color kColorHumidity      = Color(0xFF00CCCC);
const Color kColorWindSpeed     = Color(0xFF0000CC);
const Color kColorWindDirection = Color(0xFF888888);

// Alert severity colors
const Color kColorAlertExtreme  = Color(0xFFD32F2F);
const Color kColorAlertSevere   = Color(0xFFD32F2F);
const Color kColorAlertModerate = Color(0xFFF57C00);
const Color kColorAlertMinor    = Color(0xFFF9A825);

// Row names (used as keys in visibleRows map)
const String kRowTemperature   = 'Temperature';
const String kRowDewpoint      = 'Dewpoint';
const String kRowPrecip        = 'Precip. Chance';
const String kRowHumidity      = 'Humidity';
const String kRowWindSpeed     = 'Wind Speed';
const String kRowWindDirection = 'Wind Direction';
const String kRowConditions    = 'Conditions';

const List<String> kAllRows = [
  kRowTemperature,
  kRowDewpoint,
  kRowPrecip,
  kRowHumidity,
  kRowWindSpeed,
  kRowWindDirection,
  kRowConditions,
];

const Map<String, bool> kDefaultRowVisibility = {
  kRowTemperature:   true,
  kRowDewpoint:      false,
  kRowPrecip:        true,
  kRowHumidity:      true,
  kRowWindSpeed:     true,
  kRowWindDirection: true,
  kRowConditions:    true,
};
