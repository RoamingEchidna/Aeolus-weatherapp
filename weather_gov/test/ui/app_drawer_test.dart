import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_gov/models/saved_location.dart';
import 'package:weather_gov/providers/forecast_provider.dart';
import 'package:weather_gov/providers/settings_provider.dart';
import 'package:weather_gov/services/cache_service.dart';
import 'package:weather_gov/services/nws_service.dart';
import 'package:weather_gov/services/openuv_service.dart';
import 'package:weather_gov/services/usno_service.dart';
import 'package:weather_gov/ui/app_drawer.dart';

void main() {
  testWidgets('removing a location offers Undo, which puts it back',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final offline = MockClient((_) async => http.Response('', 500));
    final openUv = OpenUvService(client: offline);
    final forecast = ForecastProvider(
      nwsService: NwsService(client: offline),
      nominatimService: NominatimService(client: offline),
      cacheService: CacheService(prefs),
      usnoService: UsnoService(client: offline),
      openUvService: openUv,
      prefs: prefs,
    );
    forecast.restoreLocation(
      SavedLocation(
        displayName: 'Bishop, CA',
        lat: 37.36,
        lon: -118.39,
        lastAccessed: DateTime(2026, 1, 1),
        cachedForecast: const [],
        cachedAlerts: const [],
        cacheTimestamp: DateTime(2026, 1, 1),
      ),
      wasCurrent: true,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => SettingsProvider(prefs: prefs, openUvService: openUv)),
        ChangeNotifierProvider.value(value: forecast),
      ],
      child: const MaterialApp(home: Scaffold(body: AppDrawer())),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pump();
    expect(forecast.savedLocations, isEmpty);
    expect(find.text('Removed Bishop, CA'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(forecast.savedLocations.single.displayName, 'Bishop, CA');
    expect(find.text('Removed Bishop, CA'), findsNothing);

    // Let the undo timer's widget tree settle before the test ends.
    await tester.pump(const Duration(seconds: 9));
  });
}
