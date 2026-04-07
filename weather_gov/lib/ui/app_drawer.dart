import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/forecast_provider.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _onSearch(context, provider),
                  ),
                ),
                onSubmitted: (_) => _onSearch(context, provider),
                textInputAction: TextInputAction.search,
              ),
            ),

            // Past Locations dropdown
            if (provider.savedLocations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Past Locations',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: DropdownButton<String>(
                    value: provider.currentLocation?.displayName,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: provider.savedLocations
                        .map((loc) => DropdownMenuItem(
                              value: loc.displayName,
                              child: Text(loc.displayName,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (name) {
                      if (name == null) return;
                      final loc = provider.savedLocations
                          .firstWhere((l) => l.displayName == name);
                      Navigator.pop(context);
                      provider.selectLocation(loc);
                    },
                  ),
                ),
              ),

            // Grab new data button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: FilledButton.tonal(
                onPressed:
                    provider.isLoading || provider.currentLocation == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            provider.refreshCurrentLocation();
                          },
                child: provider.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Grab new data'),
              ),
            ),

            const Divider(height: 24),

            // Row toggles
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: kAllRows
                    .map((row) => SwitchListTile(
                          title: Text(row,
                              style: Theme.of(context).textTheme.bodyMedium),
                          value: provider.visibleRows[row] ?? true,
                          onChanged: (_) => provider.toggleRow(row),
                          dense: true,
                        ))
                    .toList(),
              ),
            ),

            const Divider(height: 1),

            // Dark mode toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SwitchListTile(
                title: Text(
                  provider.isDarkMode ? '\u263e Dark Mode' : '\u2600 Dark Mode',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                value: provider.isDarkMode,
                onChanged: (_) => provider.toggleDarkMode(),
                dense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
