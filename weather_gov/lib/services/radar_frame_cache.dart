import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Disk cache for radar frame and boundary PNGs.
///
/// Frames: `radar_{sourceKey}_{lat}_{lon}_{utcMillis}.png` — the location
/// is part of the key because frames are cropped to a bbox centered on it;
/// a frame for one location is never valid for another.
/// Boundaries: `bounds_{lat}_{lon}.png`, never evicted (they don't change).
class RadarFrameCache {
  final Directory? _overrideDir;

  /// [dir] overrides the platform cache directory (used by tests).
  RadarFrameCache({Directory? dir}) : _overrideDir = dir;

  Future<Directory> _dir() async {
    final base = _overrideDir ??
        Directory('${(await getTemporaryDirectory()).path}/radar');
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

  String _coordKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';

  Future<Map<int, Uint8List>> loadFrames(
      String sourceKey, double lat, double lon) async {
    final dir = await _dir();
    final prefix = 'radar_${sourceKey}_${_coordKey(lat, lon)}_';
    final frames = <int, Uint8List>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.png')) continue;
      final millis =
          int.tryParse(name.substring(prefix.length, name.length - 4));
      if (millis == null) continue;
      frames[millis] = await entity.readAsBytes();
    }
    return frames;
  }

  Future<void> saveFrame(String sourceKey, double lat, double lon, int millis,
      Uint8List bytes) async {
    final dir = await _dir();
    await File(
            '${dir.path}/radar_${sourceKey}_${_coordKey(lat, lon)}_$millis.png')
        .writeAsBytes(bytes);
  }

  Future<Uint8List?> loadBoundaries(double lat, double lon) async {
    final dir = await _dir();
    final file = File('${dir.path}/bounds_${_coordKey(lat, lon)}.png');
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> saveBoundaries(double lat, double lon, Uint8List bytes) async {
    final dir = await _dir();
    await File('${dir.path}/bounds_${_coordKey(lat, lon)}.png')
        .writeAsBytes(bytes);
  }

  /// Deletes radar frame files older than [cutoff], across all sources and
  /// locations. Boundary files are untouched.
  Future<void> evictOlderThan(DateTime cutoff) async {
    final dir = await _dir();
    final cutoffMillis = cutoff.millisecondsSinceEpoch;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('radar_') || !name.endsWith('.png')) continue;
      final millis =
          int.tryParse(name.split('_').last.replaceAll('.png', ''));
      if (millis != null && millis < cutoffMillis) {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort; a locked file just gets retried next eviction.
        }
      }
    }
  }
}
