import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/saved_location.dart';
import '../providers/forecast_provider.dart';
import '../providers/settings_provider.dart';
import 'app_drawer.dart';
import 'alert_banner.dart';
import 'radar_screen.dart';
import 'scrollable_chart.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tick every 30 seconds so the displayed time stays fresh.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now().toUtc());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pick up whatever the background sync wrote while the app was hidden.
    if (state == AppLifecycleState.resumed) {
      setState(() => _now = DateTime.now().toUtc());
      context.read<ForecastProvider>().reloadFromDisk();
    }
  }

  List<Widget> _locationTimeParts(SavedLocation location, bool use24Hour, BuildContext context) {
    final local = _now.add(Duration(hours: location.tzOffsetHours));
    final fmt = DateFormat(use24Hour ? 'HH:mm' : 'h:mm a');
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ?? Theme.of(context).textTheme.titleLarge;
    final systemOffsetHours = DateTime.now().timeZoneOffset.inHours;
    final diff = location.tzOffsetHours - systemOffsetHours;
    final diffStr = diff == 0 ? '' : (diff > 0 ? ' (+$diff)' : ' ($diff)');
    return [
      Text(fmt.format(local), style: titleStyle),
      if (diffStr.isNotEmpty)
        Text(diffStr, style: Theme.of(context).textTheme.labelSmall),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ForecastProvider>();
    final location = provider.currentLocation;

    return Scaffold(
      appBar: AppBar(
        title: location == null
            ? const Text('Weather Forecast')
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      location.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ..._locationTimeParts(location, context.watch<SettingsProvider>().use24Hour, context),
                ],
              ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.radar),
            tooltip: 'Radar',
            onPressed: location == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RadarScreen(location: location),
                      ),
                    ),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Ease banners in and out so the chart doesn't lurch in one frame.
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                if (location != null) AlertBanner(alerts: location.cachedAlerts),
                if (location != null) _CacheBanner(location: location),
                if (provider.errorMessage != null)
                  _ErrorBanner(message: provider.errorMessage!),
              ],
            ),
          ),
          // Space is always reserved so the chart doesn't jump 4px per refresh.
          SizedBox(
            height: 4,
            child: provider.isLoading ? const LinearProgressIndicator() : null,
          ),
          Expanded(
            child: location == null
                ? const _EmptyState()
                : location.cachedForecast.isEmpty
                    ? const Center(child: Text('No forecast data available.'))
                    : MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: MediaQuery.of(context).textScaler.clamp(
                            minScaleFactor: 0,
                            maxScaleFactor: 1.0,
                          ),
                        ),
                        child: ScrollableChart(
                          key: ValueKey(MediaQuery.of(context).orientation),
                          periods: location.cachedForecast,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _CacheBanner extends StatelessWidget {
  final SavedLocation location;

  const _CacheBanner({required this.location});

  @override
  Widget build(BuildContext context) {
    final use24Hour = context.watch<SettingsProvider>().use24Hour;
    final fmt = DateFormat(use24Hour ? 'EEE, MMM d HH:mm' : 'EEE, MMM d h:mm a');
    final timestamp = fmt.format(location.cacheTimestamp.toLocal());
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        'Data cached $timestamp',
        style: Theme.of(context).textTheme.labelSmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () =>
              context.read<ForecastProvider>().refreshCurrentLocation(),
          child: const Text('Retry'),
        ),
      ],
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wb_sunny_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('Open the menu to search for a location',
              style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
