import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_gov/constants.dart';
import 'package:weather_gov/models/hourly_period.dart';
import 'package:weather_gov/providers/forecast_provider.dart';
import 'package:weather_gov/providers/settings_provider.dart';
import 'package:weather_gov/services/cache_service.dart';
import 'package:weather_gov/services/nws_service.dart';
import 'package:weather_gov/services/openuv_service.dart';
import 'package:weather_gov/services/usno_service.dart';
import 'package:weather_gov/ui/chart_row_entries.dart';
import 'package:weather_gov/ui/scrollable_chart.dart';

List<HourlyPeriod> _periods() {
  final start = DateTime.now().toUtc().subtract(const Duration(hours: 2));
  return List.generate(48, (i) => HourlyPeriod(
        startTime: start.add(Duration(hours: i)),
        temperature: 40 + i % 12,
        precipChance: (i * 7) % 100,
        relativeHumidity: 30 + i % 50,
        dewpointF: 28,
        windSpeedMph: 5.0 + i % 15,
        windDirection: 'NW',
        shortForecast: i % 6 == 0 ? 'Chance Rain Showers' : 'Partly Cloudy',
        iconUrl: '',
        weatherTypes: i % 6 == 0 ? {'rain_showers': 'chance', 'fog': 'likely'} : null,
      ));
}

Future<Widget> _app({required bool allRows}) async {
  SharedPreferences.setMockInitialValues({
    if (allRows) for (final row in kAllRows) 'row_$row': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final offline = MockClient((_) async => http.Response('', 500));
  final openUv = OpenUvService(client: offline);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
          create: (_) => SettingsProvider(prefs: prefs, openUvService: openUv)),
      ChangeNotifierProvider(
          create: (_) => ForecastProvider(
                nwsService: NwsService(client: offline),
                nominatimService: NominatimService(client: offline),
                cacheService: CacheService(prefs),
                usnoService: UsnoService(client: offline),
                openUvService: openUv,
                prefs: prefs,
              )),
    ],
    child: MaterialApp(
      home: Scaffold(body: ScrollableChart(periods: _periods())),
    ),
  );
}

void main() {
  testWidgets('draws with the default rows', (tester) async {
    await tester.pumpWidget(await _app(allRows: false));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Temp'), findsOneWidget); // temperature legend
  });

  testWidgets('draws with every row turned on', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _app(allRows: true));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Fog'), findsOneWidget); // precip detail legend
  });

  group('computeRowHeights', () {
    test('flexible rows share what fixed rows leave over', () {
      final h = computeRowHeights(kDefaultRowVisibility, 600);
      // Temp, wind, atmos flex; conditions is a fixed 50.
      final expected =
          ((600 - h.valuePanelHeight - kTimeAxisHeight - 50) / 3).floorToDouble();
      expect(h.rowHeight, expected);
    });

    test('precip detail makes the value panel taller', () {
      final withDetail = {...kDefaultRowVisibility, kRowPrecipDetail: true};
      expect(computeRowHeights(withDetail, 600).valuePanelHeight,
          greaterThan(computeRowHeights(kDefaultRowVisibility, 600).valuePanelHeight));
    });
  });
}
