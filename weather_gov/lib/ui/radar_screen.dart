import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_location.dart';
import '../providers/forecast_provider.dart';
import '../services/radar_frame_cache.dart';
import '../services/radar_service.dart';

class RadarScreen extends StatefulWidget {
  final SavedLocation location;
  const RadarScreen({super.key, required this.location});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  static const _speedsMs = [800, 400, 200];
  static const _speedLabels = ['0.5×', '1×', '2×'];
  static const _maxAge = Duration(hours: 5);

  late final LatLonBox _bbox;
  final _cache = RadarFrameCache();
  RadarService? _service;

  Uint8List? _boundaries;
  final Map<int, Uint8List> _frames = {}; // utcMillis -> png bytes
  List<int> _times = []; // sorted keys of _frames

  int _index = 0;
  bool _playing = false;
  int _speedIdx = 1;
  Timer? _timer;

  bool _loading = true;
  String? _error; // fatal: nothing to show
  String? _notice; // non-fatal: showing cached frames

  // Incremented on every _load; each run aborts after any await if a newer
  // run has started (refresh mid-backfill) or the screen was disposed.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _bbox = LatLonBox.around(widget.location.lat, widget.location.lon, 2.0);
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _rebuildTimes() {
    _times = _frames.keys.toList()..sort();
    if (_index >= _times.length) _index = _times.isEmpty ? 0 : _times.length - 1;
  }

  /// True when [gen] is no longer the active load (a newer _load started)
  /// or the screen is gone — the stale run must stop touching state.
  bool _stale(int gen) => gen != _loadGeneration || !mounted;

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _playing = false;
    });

    final lat = widget.location.lat;
    final lon = widget.location.lon;

    try {
      // Evict stale frames from disk AND memory (refresh path re-enters here).
      final cutoff = DateTime.now().subtract(_maxAge);
      await _cache.evictOlderThan(cutoff);
      if (_stale(gen)) return;
      _frames.removeWhere(
          (millis, _) => millis < cutoff.millisecondsSinceEpoch);

      final prefs = await SharedPreferences.getInstance();
      _service ??= RadarService(prefs: prefs);
      var source = await _service!.resolveSource(lat, lon);
      if (_stale(gen)) return;

      // Boundaries: memory -> disk -> network; tolerate total failure.
      _boundaries ??= await _cache.loadBoundaries(lat, lon);
      if (_boundaries == null) {
        try {
          _boundaries = await _service!.fetchBoundaries(_bbox);
          await _cache.saveBoundaries(lat, lon, _boundaries!);
        } catch (_) {
          // Radar without boundaries is still usable.
        }
      }
      if (_stale(gen)) return;

      // Paint whatever is already cached before any network wait.
      final cached = await _cache.loadFrames(source.sourceKey, lat, lon);
      if (_stale(gen)) return;
      _frames.addAll(cached);
      _rebuildTimes();
      if (_frames.isNotEmpty) {
        setState(() {
          _loading = false;
          _index = _times.length - 1;
        });
      }

      // List available frames; a dead station falls back to composite.
      List<String> available;
      try {
        available = await _service!.fetchAvailableTimes(source);
      } catch (_) {
        if (source.isComposite) rethrow;
        source = const RadarSource.composite();
        final compCached = await _cache.loadFrames(source.sourceKey, lat, lon);
        if (_stale(gen)) return;
        _frames
          ..clear()
          ..addAll(compCached);
        _rebuildTimes();
        available = await _service!.fetchAvailableTimes(source);
      }
      if (_stale(gen)) return;

      // Fetch missing frames newest-first so current conditions paint in
      // one round-trip; older frames backfill behind it.
      final missing = available
          .where((t) =>
              !_frames.containsKey(DateTime.parse(t).millisecondsSinceEpoch))
          .toList()
          .reversed
          .toList();
      for (final t in missing) {
        try {
          final bytes = await _service!.fetchFrame(source, _bbox, t);
          final millis = DateTime.parse(t).millisecondsSinceEpoch;
          // Save to disk even if stale — the fetch already happened and the
          // next load reads it from cache. Only in-memory state is off-limits.
          await _cache.saveFrame(source.sourceKey, lat, lon, millis, bytes);
          if (_stale(gen)) return;
          _frames[millis] = bytes;
          _rebuildTimes();
          setState(() {
            _loading = false;
            _index = _times.length - 1;
          });
        } catch (_) {
          // Skip failed frames; the loop plays what it has.
          if (_stale(gen)) return;
        }
      }

      if (_stale(gen)) return;
      if (_frames.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No radar data available for this location.';
        });
        return;
      }
      setState(() => _loading = false);
      _startPlayback();
    } catch (_) {
      if (_stale(gen)) return;
      setState(() {
        _loading = false;
        if (_frames.isEmpty) {
          _error = "Couldn't load radar data.";
        } else {
          _notice = "Couldn't fetch latest radar — showing cached frames.";
          _startPlayback();
        }
      });
    }
  }

  void _startPlayback() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: _speedsMs[_speedIdx]),
      (_) {
        if (_times.isEmpty) return;
        setState(() => _index = (_index + 1) % _times.length);
      },
    );
    setState(() => _playing = true);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    setState(() => _playing = false);
  }

  void _cycleSpeed() {
    setState(() => _speedIdx = (_speedIdx + 1) % _speedsMs.length);
    if (_playing) _startPlayback();
  }

  String _frameLabel(int millis, bool use24Hour) {
    final local = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
        .add(Duration(hours: widget.location.tzOffsetHours));
    return DateFormat(use24Hour ? 'MMM d, HH:mm' : 'MMM d, h:mm a')
        .format(local);
  }

  @override
  Widget build(BuildContext context) {
    final use24Hour = context.watch<ForecastProvider>().use24Hour;
    final currentFrame =
        _times.isEmpty ? null : _frames[_times[_index]];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.location.displayName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh radar',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : Column(
              children: [
                if (_notice != null)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Text(
                      _notice!,
                      style: Theme.of(context).textTheme.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (currentFrame == null)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else ...[
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      // Fixed light background in both themes: NOAA's
                      // boundary strokes are dark and vanish on dark surfaces.
                      color: const Color(0xFFE0E0E0),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            if (_boundaries != null)
                              Positioned.fill(
                                child: Image.memory(
                                  _boundaries!,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                              ),
                            Positioned.fill(
                              child: Image.memory(
                                currentFrame,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                            ),
                            Positioned(
                              left: _bbox.xFraction(widget.location.lon) *
                                      constraints.maxWidth -
                                  5,
                              top: _bbox.yFraction(widget.location.lat) *
                                      constraints.maxHeight -
                                  5,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primary,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _frameLabel(_times[_index], use24Hour),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                              _playing ? Icons.pause : Icons.play_arrow),
                          onPressed:
                              _playing ? _pause : _startPlayback,
                        ),
                        Expanded(
                          child: Slider(
                            value: _index.toDouble(),
                            min: 0,
                            max: (_times.length - 1)
                                .clamp(1, 1 << 30)
                                .toDouble(),
                            divisions:
                                _times.length > 1 ? _times.length - 1 : 1,
                            onChangeStart: (_) => _pause(),
                            onChanged: _times.length > 1
                                ? (v) =>
                                    setState(() => _index = v.round())
                                : null,
                          ),
                        ),
                        TextButton(
                          onPressed: _cycleSpeed,
                          child: Text(_speedLabels[_speedIdx]),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
