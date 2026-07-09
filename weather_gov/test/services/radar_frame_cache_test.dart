import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_gov/services/radar_frame_cache.dart';

void main() {
  late Directory tempDir;
  late RadarFrameCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('radar_cache_test');
    cache = RadarFrameCache(dir: tempDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  final bytes = Uint8List.fromList([1, 2, 3]);

  test('saveFrame / loadFrames round-trip, keyed by source and location',
      () async {
    await cache.saveFrame('kabr', 37.36, -118.40, 1000, bytes);
    await cache.saveFrame('kabr', 37.36, -118.40, 2000, bytes);
    await cache.saveFrame('conus', 37.36, -118.40, 3000, bytes); // other source
    await cache.saveFrame('kabr', 40.00, -100.00, 4000, bytes); // other location

    final frames = await cache.loadFrames('kabr', 37.36, -118.40);
    expect(frames.keys.toSet(), {1000, 2000});
    expect(frames[1000], bytes);
  });

  test('boundaries round-trip and survive frame eviction', () async {
    expect(await cache.loadBoundaries(37.36, -118.40), isNull);
    await cache.saveBoundaries(37.36, -118.40, bytes);
    expect(await cache.loadBoundaries(37.36, -118.40), bytes);

    await cache.evictOlderThan(DateTime.now());
    expect(await cache.loadBoundaries(37.36, -118.40), bytes,
        reason: 'boundaries never expire');
  });

  test('evictOlderThan deletes only frames older than cutoff, all locations',
      () async {
    final now = DateTime.now();
    final oldMs = now.subtract(const Duration(hours: 6)).millisecondsSinceEpoch;
    final newMs = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    await cache.saveFrame('kabr', 37.36, -118.40, oldMs, bytes);
    await cache.saveFrame('kabr', 37.36, -118.40, newMs, bytes);
    await cache.saveFrame('conus', 40.00, -100.00, oldMs, bytes);

    await cache.evictOlderThan(now.subtract(const Duration(hours: 5)));

    expect((await cache.loadFrames('kabr', 37.36, -118.40)).keys.toList(),
        [newMs]);
    expect(await cache.loadFrames('conus', 40.00, -100.00), isEmpty);
  });

  test('coordinates are rounded to 2 decimals in keys', () async {
    await cache.saveFrame('kabr', 37.36123, -118.40456, 1000, bytes);
    final frames = await cache.loadFrames('kabr', 37.359, -118.401);
    expect(frames.keys.toList(), [1000]);
  });
}
