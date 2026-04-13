import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/forecast_provider.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _searchController = TextEditingController();
  List<SuggestionResult> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
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

  void _showApiKeyDialog(BuildContext context, ForecastProvider provider) {
    final controller = TextEditingController(text: provider.openUvApiKey ?? '');
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
              provider.setOpenUvApiKey(controller.text);
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
                            leading: GestureDetector(
                              onTap: () => provider.pinLocation(loc.displayName),
                              child: Icon(
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
                            trailing: GestureDetector(
                              onTap: () => provider.deleteLocation(loc.displayName),
                              child: const Icon(Icons.close, size: 18),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              provider.selectLocation(loc);
                            },
                          );
                        },
                      ),
                    ],

                    const Divider(height: 24),

                    // Row toggles — drag to reorder
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      onReorder: provider.reorderRow,
                      children: provider.rowOrder.map((row) => SwitchListTile(
                        key: ValueKey(row),
                        title: Text(row,
                            style: Theme.of(context).textTheme.bodySmall),
                        value: provider.visibleRows[row] ?? true,
                        onChanged: (_) => provider.toggleRow(row),
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
              value: provider.syncPinnedOnOpen,
              onChanged: (_) => provider.toggleSyncPinnedOnOpen(),
              title: Row(
                children: [
                  Text('Auto Sync',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  GestureDetector(
                    onTap: provider.isLoading || provider.currentLocation == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            provider.refreshCurrentLocation();
                          },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: provider.isLoading || provider.currentLocation == null
                            ? Theme.of(context).disabledColor
                            : Theme.of(context).colorScheme.primary,
                      ),
                      child: provider.isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.sync,
                              size: 18,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Dark mode toggle
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              title: Text(
                provider.isDarkMode ? 'Dark Mode' : 'Light Mode',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: provider.isDarkMode,
              onChanged: (_) => provider.toggleDarkMode(),
              dense: true,
            ),

            // °F / °C toggle
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              title: Text(
                provider.useMetric ? '°C / km/h' : '°F / mp/h',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: !provider.useMetric,
              onChanged: (_) => provider.toggleMetric(),
              dense: true,
            ),

            // 24-hour time toggle
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              title: Text(
                provider.use24Hour ? '00:00 Time' : 'AM/PM Time',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: provider.use24Hour,
              onChanged: (_) => provider.toggle24Hour(),
              dense: true,
            ),

            // OpenUV API key — only shown when no key has been set
            if (provider.openUvApiKey == null)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 12, right: 4),
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(
                  'Set OpenUV API Key',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                dense: true,
                onTap: () => _showApiKeyDialog(context, provider),
              ),
          ],
        ),
      ),
    );
  }
}
