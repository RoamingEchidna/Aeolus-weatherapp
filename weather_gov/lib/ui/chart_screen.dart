import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/saved_location.dart';
import '../providers/forecast_provider.dart';
import 'app_drawer.dart';
import 'alert_banner.dart';
import 'scrollable_chart.dart';

class ChartScreen extends StatelessWidget {
  const ChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ForecastProvider>();
    final location = provider.currentLocation;

    return Scaffold(
      appBar: AppBar(
        title: Text(location?.displayName ?? 'Weather Forecast'),
        centerTitle: false,
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          if (location != null) AlertBanner(alerts: location.cachedAlerts),
          if (location != null) _CacheBanner(location: location),
          if (provider.errorMessage != null)
            _ErrorBanner(message: provider.errorMessage!),
          if (provider.isLoading) const LinearProgressIndicator(),
          Expanded(
            child: location == null
                ? const _EmptyState()
                : location.cachedForecast.isEmpty
                    ? const Center(child: Text('No forecast data available.'))
                    : ScrollableChart(periods: location.cachedForecast),
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
    final fmt = DateFormat('EEE, MMM d h:mm a');
    final timestamp = fmt.format(location.cacheTimestamp.toLocal());
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        'Showing cached data from $timestamp',
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
