import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/forecast_provider.dart';
import '../services/plotter_service.dart';

// Y positions of each panel strip in the stitched image (same as tile0).
const _panelStripTops = [1, 141, 281, 421, 511, 601, 691, 781];
const _panelStripHeight = 12.0;
const _imageHeight = 870.0;

class StitchedChartWidget extends StatelessWidget {
  final Uint8List imageBytes;

  const StitchedChartWidget({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ForecastProvider>();
    final legendStrips = provider.legendStrips;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxHeight / _imageHeight;
        final scaledWidth = stitchedWidth * scale;

        return Stack(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: scaledWidth,
                height: constraints.maxHeight,
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.fill,
                  key: ValueKey(imageBytes.hashCode),
                ),
              ),
            ),
            if (legendStrips.isNotEmpty)
              Positioned(
                top: 0,
                right: 0,
                child: _LegendOverlay(strips: legendStrips, scale: scale),
              ),
          ],
        );
      },
    );
  }
}

class _LegendOverlay extends StatelessWidget {
  final List<Uint8List> strips;
  final double scale;

  const _LegendOverlay({required this.strips, required this.scale});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _imageHeight * scale,
      width: legendStripWidth * scale,
      child: Stack(
        children: [
          for (int i = 0; i < strips.length && i < _panelStripTops.length; i++)
            Positioned(
              top: _panelStripTops[i] * scale,
              left: 0,
              right: 0,
              height: _panelStripHeight * scale,
              child: Image.memory(strips[i], fit: BoxFit.fill),
            ),
        ],
      ),
    );
  }
}
