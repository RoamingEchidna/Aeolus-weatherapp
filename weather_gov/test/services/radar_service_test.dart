import 'package:flutter_test/flutter_test.dart';
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
}
