import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/saved_location.dart';
import '../providers/forecast_provider.dart';
import '../providers/settings_provider.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _searchController = TextEditingController();
  List<SuggestionResult> _suggestions = [];
  Timer? _debounce;
  SavedLocation? _removed;
  bool _removedWasCurrent = false;
  Timer? _undoTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Diagnostic keys are written by the background isolate, so re-read
    // them from disk whenever the drawer opens rather than trusting
    // whatever was cached in memory at app launch.
    context.read<SettingsProvider>().refreshSyncDiagnostics();
  }

  String _formatSyncDiagTime(String? iso) {
    if (iso == null) return 'never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'never';
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  void _showBatteryOptimizationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep background sync reliable'),
        content: const Text(
          "Android's battery optimization can delay or block nightly "
          "background syncs on some phones. For sync to run reliably, set "
          "Aeolus's battery setting to Unrestricted.\n\n"
          'You can change this anytime in Settings → Apps → Aeolus → Battery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openBatterySettings();
            },
            child: const Text('Open Battery Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _openBatterySettings() async {
    const pkg = 'com.weathergov.weather_gov';
    // Deep-links straight to the app's Battery settings page on stock
    // Android; falls back to the general App Info page if unsupported.
    final primary = Uri.parse(
        'intent:package:$pkg#Intent;action=android.settings.APP_BATTERY_SETTINGS;end');
    final fallback = Uri.parse(
        'intent:package:$pkg#Intent;action=android.settings.APPLICATION_DETAILS_SETTINGS;end');
    try {
      final opened =
          await launchUrl(primary, mode: LaunchMode.externalApplication);
      if (opened) return;
    } catch (_) {}
    try {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _removeLocation(ForecastProvider provider, SavedLocation loc) {
    _undoTimer?.cancel();
    setState(() {
      _removed = loc;
      _removedWasCurrent =
          loc.displayName == provider.currentLocation?.displayName;
    });
    provider.deleteLocation(loc.displayName);
    _undoTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _removed = null);
    });
  }

  void _undoRemove(ForecastProvider provider) {
    final loc = _removed;
    if (loc == null) return;
    _undoTimer?.cancel();
    provider.restoreLocation(loc, wasCurrent: _removedWasCurrent);
    setState(() => _removed = null);
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final provider = context.read<ForecastProvider>();
      final results = await provider.getSuggestions(query);
      if (mounted) setState(() => _suggestions = results);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _suggestions = []);
  }

  void _showApiKeyDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(text: settings.openUvApiKey ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenUV API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Paste your key here',
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://www.openuv.io/'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                'Get an API key at openuv.io to display UV Index',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settings.setOpenUvApiKey(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _onSearch(BuildContext context, ForecastProvider provider) {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    Navigator.pop(context);
    provider.searchLocation(query);
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ForecastProvider>();
    final settings = context.watch<SettingsProvider>();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scrollable top section
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search location...',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: _clearSearch,
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _onSearch(context, provider),
                        textInputAction: TextInputAction.search,
                      ),
                    ),

                    // Suggestions
                    if (_suggestions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(4),
                          child: Column(
                            children: _suggestions.map((s) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on_outlined, size: 18),
                              title: Text(s.shortName,
                                  style: Theme.of(context).textTheme.bodySmall),
                              onTap: () {
                                _clearSearch();
                                Navigator.pop(context);
                                provider.selectSuggestion(s);
                              },
                            )).toList(),
                          ),
                        ),
                      ),

                    const SizedBox(height: 5),

                    // Past locations list
                    if (provider.savedLocations.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        child: Text('Past Locations',
                            style: Theme.of(context).textTheme.labelSmall),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: provider.savedLocations.length,
                        itemBuilder: (context, i) {
                          final loc = provider.savedLocations[i];
                          final isCurrent =
                              loc.displayName == provider.currentLocation?.displayName;
                          return ListTile(
                            dense: true,
                            selected: isCurrent,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            leading: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: loc.isPinned ? 'Unpin' : 'Pin',
                              onPressed: () => provider.pinLocation(loc.displayName),
                              icon: Icon(
                                loc.isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              loc.displayName,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Remove',
                              onPressed: () => _removeLocation(provider, loc),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              provider.selectLocation(loc);
                            },
                          );
                        },
                      ),
                    ],

                    // Undo for the last removal; outside the list above so it
                    // still shows after removing the only location.
                    if (_removed != null)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 12, right: 4),
                        title: Text(
                          'Removed ${_removed!.displayName}',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: () => _undoRemove(provider),
                          child: const Text('Undo'),
                        ),
                      ),

                    const Divider(height: 24),

                    // Row toggles — drag to reorder
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      onReorder: settings.reorderRow,
                      children: settings.rowOrder.map((row) => SwitchListTile(
                        key: ValueKey(row),
                        title: Text(row,
                            style: Theme.of(context).textTheme.bodySmall),
                        value: settings.visibleRows[row] ?? true,
                        onChanged: (_) => settings.toggleRow(row),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        secondary: const Icon(Icons.drag_handle, size: 18),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),

            // Fixed bottom section
            const Divider(height: 16),

            // Auto Sync toggle + manual refresh button
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              value: settings.syncPinnedOnOpen,
              onChanged: (_) {
                final turningOn = !settings.syncPinnedOnOpen;
                settings.toggleSyncPinnedOnOpen();
                if (turningOn && settings.shouldShowBatteryWarning) {
                  settings.recordBatteryWarningShown();
                  _showBatteryOptimizationDialog(context);
                }
              },
              title: Row(
                children: [
                  Text('Auto Sync',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  // Drawn at 28px, but keeps Android's 48dp tap area.
                  IconButton.filled(
                    tooltip: 'Sync pinned now',
                    onPressed: provider.isLoading ||
                            !provider.savedLocations.any((l) => l.isPinned)
                        ? null
                        : () {
                            Navigator.pop(context);
                            provider.refreshPinnedLocations();
                          },
                    style: IconButton.styleFrom(
                      fixedSize: const Size(28, 28),
                      minimumSize: const Size(28, 28),
                      padding: EdgeInsets.zero,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      disabledBackgroundColor: Theme.of(context).disabledColor,
                      disabledForegroundColor:
                          Theme.of(context).colorScheme.onPrimary,
                    ),
                    icon: provider.isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.sync, size: 18),
                  ),
                ],
              ),
              subtitle: settings.syncPinnedOnOpen
                  ? Text(
                      'Last attempt: ${_formatSyncDiagTime(settings.lastSyncAttemptAt)}'
                      ' (${settings.lastSyncResult ?? "pending"})\n'
                      'Next scheduled: ${_formatSyncDiagTime(settings.nextSyncScheduledFor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : null,
            ),

            // Severe Weather Alerts toggle (requires Auto Sync)
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              value: settings.severeWeatherNotifications,
              onChanged: settings.syncPinnedOnOpen
                  ? (_) async {
                      if (!settings.severeWeatherNotifications) {
                        await FlutterLocalNotificationsPlugin()
                            .resolvePlatformSpecificImplementation<
                                AndroidFlutterLocalNotificationsPlugin>()
                            ?.requestNotificationsPermission();
                      }
                      settings.toggleSevereWeatherNotifications();
                    }
                  : null,
              title: Text(
                'Severe Weather Alerts',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),

            // Dark mode toggle
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              title: Text(
                settings.isDarkMode ? 'Dark Mode' : 'Light Mode',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: settings.isDarkMode,
              onChanged: (_) => settings.toggleDarkMode(),
              dense: true,
            ),

            // °F / °C toggle
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              title: Text(
                settings.useMetric ? '°C / km/h' : '°F / mp/h',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: !settings.useMetric,
              onChanged: (_) => settings.toggleMetric(),
              dense: true,
            ),

            // 24-hour time toggle
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              title: Text(
                settings.use24Hour ? '00:00 Time' : 'AM/PM Time',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: settings.use24Hour,
              onChanged: (_) => settings.toggle24Hour(),
              dense: true,
            ),

            // OpenUV API key — only shown when no key has been set
            if (settings.openUvApiKey == null)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 12, right: 4),
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(
                  'Set OpenUV API Key',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                dense: true,
                onTap: () => _showApiKeyDialog(context, settings),
              ),
          ],
        ),
      ),
    );
  }
}
