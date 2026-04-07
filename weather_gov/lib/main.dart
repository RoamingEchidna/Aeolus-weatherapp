import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'providers/forecast_provider.dart';
import 'services/nws_service.dart';
import 'services/nominatim_service.dart';
import 'services/cache_service.dart';
import 'ui/chart_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final client = http.Client();

  final provider = ForecastProvider(
    nwsService: NwsService(client: client),
    nominatimService: NominatimService(client: client),
    cacheService: CacheService(prefs),
    prefs: prefs,
  );
  await provider.init();

  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const WeatherApp(),
    ),
  );
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<ForecastProvider, bool>((p) => p.isDarkMode);
    return MaterialApp(
      title: 'Weather Forecast',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const ChartScreen(),
    );
  }
}
