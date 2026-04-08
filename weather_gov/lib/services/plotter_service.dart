import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'nws_service.dart';

// Pixel measurements from canvas analysis of Plotter.php output:
//   Image: 800 x 870 px
//   Legend strip: x=570–799 (230px wide)
//   Panel header y-ranges (where the legend text sits):
const _legendX = 570;
const _legendW = 230; // 800 - 570
const _tileW = 800;
const _tileH = 870;

// Each panel header strip in a tile (top-inclusive, bottom-exclusive).
const _panelStrips = [
  (y: 1, h: 12),
  (y: 141, h: 12),
  (y: 281, h: 11),
  (y: 421, h: 11),
  (y: 511, h: 11),
  (y: 601, h: 11),
  (y: 691, h: 11),
  (y: 781, h: 11),
];

// Left y-axis width that we crop from tiles 2 & 3 when stitching.
const _leftAxisW = 54;

// Total stitched width: tile0(800) + tile1(800-54) + tile2(800-54) = 2292
const stitchedWidth = _tileW + (_tileW - _leftAxisW) * 2;

// Legend strip dimensions for the overlay widget.
const legendStripWidth = _legendW;

class PlotterResult {
  /// Raw PNG bytes of the stitched image (held in memory).
  final Uint8List stitchedBytes;

  /// One PNG per panel strip extracted from tile 0, used for the overlay.
  final List<Uint8List> legendStrips;

  const PlotterResult({
    required this.stitchedBytes,
    required this.legendStrips,
  });
}

class PlotterService {
  final http.Client _client;
  static const _headers = {'User-Agent': 'WeatherGovApp/1.0'};

  PlotterService({http.Client? client}) : _client = client ?? http.Client();

  Uri _buildUri(PlotterParams p, double lat, double lon, int ahour, String pcmd) {
    return Uri.https(
      'forecast.weather.gov',
      '/meteograms/Plotter.php',
      {
        'lat': lat.toStringAsFixed(4),
        'lon': lon.toStringAsFixed(4),
        'wfo': p.wfo,
        'zcode': p.zcode,
        'gset': '18',
        'gdiff': '5',
        'unit': '0',
        'tinfo': p.tinfo,
        'ahour': ahour.toString(),
        'pcmd': pcmd,
        'lg': 'en',
        'indu': '1!1!1!',
        'dd': '',
        'bw': '',
        'hrspan': '48',
        'pqpfhr': '6',
        'psnwhr': '6',
      },
    );
  }

  Future<img.Image> _fetchTile(
      PlotterParams p, double lat, double lon, int ahour, String pcmd) async {
    final uri = _buildUri(p, lat, lon, ahour, pcmd);
    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('Plotter.php error ${resp.statusCode} for ahour=$ahour');
    }
    final decoded = img.decodeImage(resp.bodyBytes);
    if (decoded == null) throw Exception('Failed to decode tile ahour=$ahour');
    return decoded;
  }

  /// Erases the legend region (x=570–799) in each panel header strip by
  /// filling those pixels with the background color sampled from x=565.
  void _eraseLegend(img.Image tile) {
    for (final strip in _panelStrips) {
      for (int dy = 0; dy < strip.h; dy++) {
        final y = strip.y + dy;
        if (y >= tile.height) continue;
        final bgPixel = tile.getPixel(565, y);
        for (int x = _legendX; x < _tileW; x++) {
          tile.setPixel(x, y, bgPixel);
        }
      }
    }
  }

  /// Extracts the legend strips from tile 0 before erasing them.
  List<Uint8List> _extractLegends(img.Image tile) {
    final result = <Uint8List>[];
    for (final strip in _panelStrips) {
      final cropped = img.copyCrop(
        tile,
        x: _legendX,
        y: strip.y,
        width: _legendW,
        height: strip.h,
      );
      result.add(Uint8List.fromList(img.encodePng(cropped)));
    }
    return result;
  }

  /// Fetches 3 tiles, erases legends, stitches, returns PNG bytes + legend strips.
  Future<PlotterResult> fetchAndStitch(
      PlotterParams params, double lat, double lon, String pcmd) async {
    final futures = await Future.wait([
      _fetchTile(params, lat, lon, 0, pcmd),
      _fetchTile(params, lat, lon, 48, pcmd),
      _fetchTile(params, lat, lon, 96, pcmd),
    ]);

    final tile0 = futures[0];
    final tile1 = futures[1];
    final tile2 = futures[2];

    final legendStrips = _extractLegends(tile0);

    _eraseLegend(tile0);
    _eraseLegend(tile1);
    _eraseLegend(tile2);

    final stitched = img.Image(width: stitchedWidth, height: _tileH);
    img.compositeImage(stitched, tile0, dstX: 0, dstY: 0);

    final crop1 = img.copyCrop(tile1,
        x: _leftAxisW, y: 0, width: _tileW - _leftAxisW, height: _tileH);
    img.compositeImage(stitched, crop1, dstX: _tileW, dstY: 0);

    final crop2 = img.copyCrop(tile2,
        x: _leftAxisW, y: 0, width: _tileW - _leftAxisW, height: _tileH);
    img.compositeImage(stitched, crop2,
        dstX: _tileW + (_tileW - _leftAxisW), dstY: 0);

    return PlotterResult(
      stitchedBytes: Uint8List.fromList(img.encodePng(stitched)),
      legendStrips: legendStrips,
    );
  }
}
