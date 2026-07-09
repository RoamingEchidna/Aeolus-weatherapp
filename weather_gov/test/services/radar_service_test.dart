import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_gov/services/radar_service.dart';

const _kCapabilitiesXml = '''
<WMS_Capabilities>
  <Layer>
    <Name>kabr_sr_bref</Name>
    <Title>NEXRAD Level 3 Super Resolution Radar Base Reflectivity</Title>
    <Dimension name="time" default="2026-07-08T18:11:00Z" units="ISO8601">2026-07-08T17:57:07.000Z,2026-07-08T16:13:01.000Z,2026-07-08T18:11:00.000Z</Dimension>
  </Layer>
  <Layer>
    <Name>kabr_sr_bvel</Name>
    <Dimension name="time" default="x" units="ISO8601">2026-07-08T01:01:01.000Z</Dimension>
  </Layer>
</WMS_Capabilities>
''';

const _kStationsJson = '''
{
  "features": [
    {
      "geometry": {"type": "Point", "coordinates": [-118.5, 37.4]},
      "properties": {"id": "KNEAR", "stationType": "WSR-88D"}
    },
    {
      "geometry": {"type": "Point", "coordinates": [-100.0, 40.0]},
      "properties": {"id": "KFAR", "stationType": "WSR-88D"}
    },
    {
      "geometry": {"type": "Point", "coordinates": [-118.40, 37.36]},
      "properties": {"id": "TTDWR", "stationType": "TDWR"}
    }
  ]
}
''';

void main() {
  group('LatLonBox', () {
    test('around() builds a box of ±half degrees', () {
      final box = LatLonBox.around(37.36, -118.40, 2.0);
      expect(box.minLon, -120.40);
      expect(box.minLat, 35.36);
      expect(box.maxLon, -116.40);
      expect(box.maxLat, 39.36);
      expect(box.bboxParam, '-120.40,35.36,-116.40,39.36');
    });

    test('fractions map lon/lat into 0..1, y inverted', () {
      final box = LatLonBox.around(37.36, -118.40, 2.0);
      expect(box.xFraction(-118.40), closeTo(0.5, 1e-9));
      expect(box.yFraction(37.36), closeTo(0.5, 1e-9));
      expect(box.xFraction(box.minLon), 0.0);
      expect(box.yFraction(box.maxLat), 0.0); // top of image = max lat
    });
  });

  group('RadarSource', () {
    test('station source lowercases ids in layer and URL', () {
      const s = RadarSource.station('KABR');
      expect(s.isComposite, isFalse);
      expect(s.sourceKey, 'kabr');
      expect(s.layerName, 'kabr_sr_bref');
      expect(s.owsBase,
          'https://opengeo.ncep.noaa.gov/geoserver/kabr/ows');
    });

    test('composite source uses conus layer', () {
      const s = RadarSource.composite();
      expect(s.isComposite, isTrue);
      expect(s.sourceKey, 'conus');
      expect(s.layerName, 'conus_bref_qcd');
      expect(s.owsBase,
          'https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows');
    });
  });

  group('RadarService.parseTimeDimension', () {
    test('extracts verbatim timestamps for the right layer, sorted ascending',
        () {
      final times =
          RadarService.parseTimeDimension(_kCapabilitiesXml, 'kabr_sr_bref');
      expect(times, [
        '2026-07-08T16:13:01.000Z',
        '2026-07-08T17:57:07.000Z',
        '2026-07-08T18:11:00.000Z',
      ]);
    });

    test('returns empty list when layer missing', () {
      expect(RadarService.parseTimeDimension(_kCapabilitiesXml, 'nope'), isEmpty);
    });
  });

  group('RadarService.resolveSource', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    RadarService service(String body, {int status = 200}) => RadarService(
          client: MockClient((_) async => http.Response(body, status)),
          prefs: prefs,
        );

    test('picks nearest WSR-88D station, ignoring closer TDWR', () async {
      final s = await service(_kStationsJson).resolveSource(37.36, -118.40);
      expect(s.stationId, 'KNEAR');
    });

    test('falls back to composite when nearest station > 200 km', () async {
      // (30.0, -90.0) is ~1000+ km from both WSR-88D stations.
      final s = await service(_kStationsJson).resolveSource(30.0, -90.0);
      expect(s.isComposite, isTrue);
    });

    test('falls back to composite on HTTP error, without persisting it',
        () async {
      final s = await service('oops', status: 500).resolveSource(37.36, -118.40);
      expect(s.isComposite, isTrue);
      // Failure must NOT be cached — a later retry should hit the network.
      expect(prefs.getString('radarSource_37.36_-118.40'), isNull);
    });

    test('caches successful resolution and reuses it without a request',
        () async {
      await service(_kStationsJson).resolveSource(37.36, -118.40);
      expect(prefs.getString('radarSource_37.36_-118.40'), 'KNEAR');

      // Second service whose client would fail if called.
      final s2 = await service('boom', status: 500).resolveSource(37.36, -118.40);
      expect(s2.stationId, 'KNEAR');
    });
  });
}
