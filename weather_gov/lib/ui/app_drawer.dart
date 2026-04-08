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

            const SizedBox(height: 5),

            // Past locations list
            if (provider.savedLocations.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text('Past Locations',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: ListView.builder(
                  shrinkWrap: true,
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
                        icon: Icon(
                          loc.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 18,
                        ),
                        tooltip: loc.isPinned ? 'Unpin' : 'Pin',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => provider.pinLocation(loc.displayName),
                      ),
                      title: Text(
                        loc.displayName,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          provider.deleteLocation(loc.displayName);
                          if (isCurrent) Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        provider.selectLocation(loc);
                      },
                    );
                  },
                ),
              ),
            ],

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

            const Divider(height: 16),

            // Auto Sync toggle + manual refresh button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SwitchListTile(
                dense: true,
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
            ),

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
