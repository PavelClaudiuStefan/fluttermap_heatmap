import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:flutter_map_heatmap/src/heatmap/heat_map_generator_v2.dart';
import 'package:flutter_map_heatmap/src/plugin/heatmap_utils.dart';
import 'package:isolate_manager/isolate_manager.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

Map<TileCoordinates, bool> _initiatedTiles = {};
Map<TileCoordinates, bool> _generatedTiles = {};

List<int> _initiationTimesInMicroseconds = [];
List<int> _generationTimesInMicroseconds = [];
List<int> _filteringTimesInMicroseconds = [];

class HeatMapTilesProviderV2 extends TileProvider {
  final IsolateManager<List<DataPoint>, DataFilteringParams> filterDataIsolateManager;

  HeatMapDataSource dataSource;
  HeatMapOptions heatMapOptions;

  late Map<double, List<DataPoint>> griddedData;

  HeatMapTilesProviderV2({required this.filterDataIsolateManager, required this.dataSource, required this.heatMapOptions});

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final isDebugging = kDebugMode && false;

    final s = Stopwatch()..start();

    var tileDimension = options.tileDimension;

    // disable zoom level 0 for now. need to refactor _filterData
    // List<DataPoint> filteredData = coordinates.z != 0 ? _filterData(coordinates, options) : [];
    var scale = coordinates.z / 22 * 1.22;
    final radius = heatMapOptions.radius * scale;

    var imageHMOptions = HeatMapOptions(
      radius: radius,
      minOpacity: heatMapOptions.minOpacity,
      gradient: heatMapOptions.gradient,
    );

    s.stop();
    _initiationTimesInMicroseconds.add(s.elapsedMicroseconds);
    if (isDebugging) {
      print('\n----------------------------------------\n'
          'HeatMapTilesProvider - getImage\n'
          '${s.elapsedMilliseconds < 1 ? '' : (s.elapsedMilliseconds > 3 ? 'WARNING ' : 'DEBUG ')}'
          'Elapsed: ${s.elapsedMilliseconds} ms / ${s.elapsedMicroseconds} μs\n'
          // 'filteredData: ${filteredData.length} points\n'
          'x=${coordinates.x} / y=${coordinates.y} / z=${coordinates.z}\n'
          'tileDimension: $tileDimension\n'
          'options: $options\n'
          '----------------------------------------\n');
    }

    if (_initiatedTiles[coordinates] == null) {
      _initiatedTiles[coordinates] = true;
    } else {
      if (isDebugging) {
        print(
          '\n----------------------------------------\n'
          'WARNING Tile already initiated: x=${coordinates.x} / y=${coordinates.y} / z=${coordinates.z}\n'
          '----------------------------------------\n',
        );
      }
    }

    return HeatMapImageV2(
      filterDataIsolateManager,
      coordinates,
      dataSource,
      options,
      imageHMOptions,
      tileDimension,
    );
  }

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final isDebugging = kDebugMode && false;

    final s = Stopwatch()..start();

    var tileDimension = options.tileDimension;

    // disable zoom level 0 for now. need to refactor _filterData
    // List<DataPoint> filteredData = coordinates.z != 0 ? _filterData(coordinates, options) : [];
    var scale = coordinates.z / 22 * 1.22;
    final radius = heatMapOptions.radius * scale;

    var imageHMOptions = HeatMapOptions(
      radius: radius,
      minOpacity: heatMapOptions.minOpacity,
      gradient: heatMapOptions.gradient,
    );

    s.stop();
    _initiationTimesInMicroseconds.add(s.elapsedMicroseconds);
    if (isDebugging) {
      print('\n----------------------------------------\n'
          'HeatMapTilesProvider - getImage\n'
          '${s.elapsedMilliseconds < 1 ? '' : (s.elapsedMilliseconds > 3 ? 'WARNING ' : 'DEBUG ')}'
          'Elapsed: ${s.elapsedMilliseconds} ms / ${s.elapsedMicroseconds} μs\n'
          // 'filteredData: ${filteredData.length} points\n'
          'x=${coordinates.x} / y=${coordinates.y} / z=${coordinates.z}\n'
          'tileDimension: $tileDimension\n'
          'options: $options\n'
          '----------------------------------------\n');
    }

    if (_initiatedTiles[coordinates] == null) {
      _initiatedTiles[coordinates] = true;
    } else {
      if (isDebugging) {
        print(
          '\n----------------------------------------\n'
          'WARNING Tile already initiated: x=${coordinates.x} / y=${coordinates.y} / z=${coordinates.z}\n'
          '----------------------------------------\n',
        );
      }
    }

    return HeatMapImageV2(
      filterDataIsolateManager,
      coordinates,
      dataSource,
      options,
      imageHMOptions,
      tileDimension,
    );
  }

  /// hyperbolic sine implementation
  static double _sinh(double angle) {
    return (math.exp(angle) - math.exp(-angle)) / 2;
  }

  /// converts tile y to latitude. if the latitude is out of range it is adjusted to the min/max
  /// latitude (-90,90)
  double tile2Lat(num y, num z) {
    var yBounded = math.max(y, 0);
    var n = math.pow(2.0, z);
    var latRad = math.atan(_sinh(math.pi * (1 - 2 * yBounded / n)));
    var latDeg = latRad * 180 / math.pi;
    //keep the point in the world
    return latDeg > 0 ? math.min(latDeg, 90).toDouble() : math.max(latDeg, -90).toDouble();
  }

  /// converts the tile x to longitude. if the longitude is out of range then it is adjusted to the
  /// min/max longitude (-180/180)
  double tile2Lon(num x, num z) {
    var xBounded = math.max(x, 0);
    var lonDeg = xBounded / math.pow(2.0, z) * 360 - 180;
    return lonDeg > 0 ? math.min(lonDeg, 180).toDouble() : math.max(lonDeg, -180).toDouble();
  }
}

class HeatMapImageV2 extends ImageProvider<HeatMapImageV2> {
  final IsolateManager<List<DataPoint>, DataFilteringParams> filterDataIsolateManager;

  final TileCoordinates coordinates;

  // final List<DataPoint> data;
  final HeatMapDataSource dataSource;

  final TileLayer tileLayerOptions;

  final HeatMapV2 generator;

  HeatMapImageV2(
    this.filterDataIsolateManager,
    this.coordinates,
    this.dataSource,
    this.tileLayerOptions,
    HeatMapOptions heatmapOptions,
    int size,
  ) : generator = HeatMapV2(
          heatmapOptions,
          size,
          size,
          // data,
        );

  @override
  ImageStreamCompleter loadImage(HeatMapImageV2 key, decode) {
    return MultiFrameImageStreamCompleter(codec: _generate(), scale: 1);
  }

  Future<ui.Codec> _generate() async {
    final isDebugging = kDebugMode && false;

    if (isDebugging) {
      if (_generatedTiles[coordinates] == null) {
        _generatedTiles[coordinates] = true;
      } else {
        if (kDebugMode) {
          print(
            '\n----------------------------------------\n'
            'WARNING Tile already generated: x=${coordinates.x} / y=${coordinates.y} / z=${coordinates.z}\n'
            '----------------------------------------\n',
          );
        }
      }
    }

    final s = Stopwatch()..start();

    final DataFilteringParams dataFilteringParams = (
      dataSource: dataSource,
      coords: coordinates,
      tileDimension: tileLayerOptions.tileDimension,
      maxZoom: tileLayerOptions.maxZoom,
    );

    List<DataPoint> filteredData = coordinates.z != 0 ? await filterDataIsolateManager(dataFilteringParams) : [];

    if (isDebugging) {
      _filteringTimesInMicroseconds.add(s.elapsedMicroseconds);
      print('\n(_generate) > filteredData: ${filteredData.length} points\n');
      s.reset();
    }

    var bytes = await generator.generate(filteredData);
    var buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final result = await PaintingBinding.instance.instantiateImageCodecWithSize(buffer);

    s.stop();

    if (isDebugging) {
      _generationTimesInMicroseconds.add(s.elapsedMicroseconds);

      print(
        '\n----------------------------------------\n'
        'HeatMapImageV2 stats: ${_initiationTimesInMicroseconds.length} initiation times, ${_generationTimesInMicroseconds.length} generation times\n'
        'latest filteredData: ${filteredData.length} points\n'
        // 'initiation: \n'
        // '     latest = ${_initiationTimesInMicroseconds.last / 1000} ms\n'
        // '        min = ${_initiationTimesInMicroseconds.reduce(math.min) / 1000} ms\n'
        // '        max = ${_initiationTimesInMicroseconds.reduce(math.max) / 1000} ms\n'
        // '    average = ${_initiationTimesInMicroseconds.average / 1000} ms\n'
        // '     median = ${_median(_initiationTimesInMicroseconds) / 1000} ms\n'
        'filtering: \n'
        '     latest = ${_filteringTimesInMicroseconds.last / 1000} ms\n'
        '        min = ${_filteringTimesInMicroseconds.reduce(math.min) / 1000} ms\n'
        '        max = ${_filteringTimesInMicroseconds.reduce(math.max) / 1000} ms\n'
        '    average = ${_filteringTimesInMicroseconds.average / 1000} ms\n'
        '     median = ${_median(_filteringTimesInMicroseconds) / 1000} ms\n'
        'filtering last 100 values: \n'
        '        min = ${_filteringTimesInMicroseconds.take(100).reduce(math.min) / 1000} ms\n'
        '        max = ${_filteringTimesInMicroseconds.take(100).reduce(math.max) / 1000} ms\n'
        '    average = ${_filteringTimesInMicroseconds.take(100).average / 1000} ms\n'
        '     median = ${_median(_filteringTimesInMicroseconds.take(100)) / 1000} ms\n'
        'generation: \n'
        '     latest = ${_generationTimesInMicroseconds.last / 1000} ms\n'
        '        min = ${_generationTimesInMicroseconds.reduce(math.min) / 1000} ms\n'
        '        max = ${_generationTimesInMicroseconds.reduce(math.max) / 1000} ms\n'
        '    average = ${_generationTimesInMicroseconds.average / 1000} ms\n'
        '     median = ${_median(_generationTimesInMicroseconds) / 1000} ms\n'
        '----------------------------------------\n',
      );
    }

    return result;
  }

  double _median(Iterable<int> nrs) {
    final sorted = nrs.sorted((n1, n2) => n1.compareTo(n2));
    var middle = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[middle].toDouble();
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }

  @override
  Future<HeatMapImageV2> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }
}
