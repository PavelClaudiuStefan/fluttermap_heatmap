import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:meta/meta.dart';
import 'package:latlong2/latlong.dart';

typedef DataFilteringParams = ({
  HeatMapDataSource dataSource,
// List<WeightedLatLngV2> points,
  TileCoordinates coords,
// TileLayer options,
  int tileDimension,
  double maxZoom,
});

/// wraps a LatLng with an intensity
@immutable
class WeightedLatLngV2 {
  const WeightedLatLngV2(this.latLng, this.intensity);

  final LatLng latLng;
  final double intensity;

  @override
  String toString() {
    return 'WeightedLatLngV2{latLng: $latLng, intensity: $intensity}';
  }

  /// merge weighted lat long value the current WeightedLatLng,
  WeightedLatLngV2 merge(double x, double y, double intensity) {
    var newX = (x * intensity + latLng.longitude * this.intensity) / (intensity + this.intensity);
    var newY = (y * intensity + latLng.latitude * this.intensity) / (intensity + this.intensity);

    return WeightedLatLngV2(
      LatLng(newY, newX),
      this.intensity + intensity,
    );
  }
}

/// data point representing an x, y coordinate with an intensity
@immutable
class DataPointV2 {
  final double x;
  final double y;
  final double z;

  const DataPointV2(this.x, this.y, this.z);

  factory DataPointV2.fromOffset(Offset offset) {
    return DataPointV2(offset.dx, offset.dy, 1);
  }

  DataPointV2 merge(double x, double y, double intensity) {
    return DataPointV2(
      (x * intensity + this.x * z) / (intensity + z),
      (y * intensity + this.y * z) / (intensity + z),
      z + intensity,
    );
  }
}

class HeatMapTilesUtils {
  static List<DataPoint> filterDataDebugTest(HeatMapDataSource dataSource) {
    return List.generate(10, (i) => DataPoint(i.toDouble(), i.toDouble(), i.toDouble()));
  }

  static List<DataPoint> filterData(DataFilteringParams params) {
    List<DataPoint> filteredData = [];
    final zoom = params.coords.z;
    final scale = params.coords.z / 22 * 1.22;
    final radius = 25 * scale;
    // final tileDimension = params.options.tileDimension;
    // final maxZoom = params.options.maxZoom;
    final tileDimension = params.tileDimension;
    final maxZoom = params.maxZoom;
    final bounds = getBounds(params.coords, 1);
    final points = params.dataSource.getData(bounds, zoom.toDouble());
    // final points = params.points;
    final v = 1 / math.pow(2, math.max(0, math.min(maxZoom - zoom, 12)));

    final cellSize = radius / 2;

    final gridOffset = tileDimension;
    final gridSize = tileDimension + gridOffset;

    var gridLength = (gridSize / cellSize).ceil() + 2 + gridOffset.ceil();
    List<List<DataPointV2?>> grid = List<List<DataPointV2?>>.filled(gridLength, [], growable: true);

    const crs = Epsg3857();

    var localMin = 0.0;
    var localMax = 0.0;
    Offset tileOffset = Offset(
      (params.tileDimension * params.coords.x).toDouble(),
      (params.tileDimension * params.coords.y).toDouble(),
    );
    for (final point in points) {
      if (bounds.contains(point.latLng)) {
        var pixel = crs.latLngToOffset(point.latLng, zoom.toDouble()) - tileOffset;

        final x = ((pixel.dx) ~/ cellSize) + 2 + gridOffset.ceil();
        final y = ((pixel.dy) ~/ cellSize) + 2 + gridOffset.ceil();

        var alt = point.intensity;
        final k = alt * v;

        grid[y] = grid[y]..length = (gridSize / cellSize).ceil() + 2 + gridOffset.ceil();
        var cell = grid[y][x];

        if (cell == null) {
          grid[y][x] = DataPointV2(pixel.dx, pixel.dy, k);
          cell = grid[y][x];
        } else {
          cell.merge(pixel.dx, pixel.dy, k);
        }
        localMax = math.max(cell!.z, localMax);
        localMin = math.min(cell.z, localMin);

        if (bounds.contains(point.latLng)) {
          filteredData.add(DataPoint(pixel.dx, pixel.dy, k));
        }
      }
    }

    return filteredData;
  }

  static List<DataPoint> filterDataLegacy(HeatMapDataSource dataSource, TileCoordinates coords, TileLayer options) {
    List<DataPoint> filteredData = [];
    final zoom = coords.z;
    var scale = coords.z / 22 * 1.22;
    final radius = 25 * scale;
    var size = options.tileDimension;
    final maxZoom = options.maxZoom;
    final bounds = getBounds(coords, 1);
    final points = dataSource.getData(bounds, zoom.toDouble());
    final v = 1 / math.pow(2, math.max(0, math.min(maxZoom - zoom, 12)));

    final cellSize = radius / 2;

    final gridOffset = size;
    final gridSize = size + gridOffset;

    var gridLength = (gridSize / cellSize).ceil() + 2 + gridOffset.ceil();
    List<List<DataPoint?>> grid = List<List<DataPoint?>>.filled(gridLength, [], growable: true);

    const crs = Epsg3857();

    var localMin = 0.0;
    var localMax = 0.0;
    Offset tileOffset = Offset((options.tileDimension * coords.x).toDouble(), (options.tileDimension * coords.y).toDouble());
    for (final point in points) {
      if (bounds.contains(point.latLng)) {
        var pixel = crs.latLngToOffset(point.latLng, zoom.toDouble()) - tileOffset;

        final x = ((pixel.dx) ~/ cellSize) + 2 + gridOffset.ceil();
        final y = ((pixel.dy) ~/ cellSize) + 2 + gridOffset.ceil();

        var alt = point.intensity;
        final k = alt * v;

        grid[y] = grid[y]..length = (gridSize / cellSize).ceil() + 2 + gridOffset.ceil();
        var cell = grid[y][x];

        if (cell == null) {
          grid[y][x] = DataPoint(pixel.dx, pixel.dy, k);
          cell = grid[y][x];
        } else {
          cell.merge(pixel.dx, pixel.dy, k);
        }
        localMax = math.max(cell!.z, localMax);
        localMin = math.min(cell.z, localMin);

        if (bounds.contains(point.latLng)) {
          filteredData.add(DataPoint(pixel.dx, pixel.dy, k));
        }
      }
    }

    return filteredData;
  }

  /// extract bounds from tile coordinates. An optional [buffer] can be passed to expand the bounds
  /// to include a buffer. eg. a buffer of 0.5 would add a half tile buffer to all sides of the bounds.
  static LatLngBounds getBounds(TileCoordinates coords, [double buffer = 0]) {
    var sw = LatLng(tile2Lat(coords.y + 1 + buffer, coords.z), tile2Lon(coords.x - buffer, coords.z));
    var ne = LatLng(tile2Lat(coords.y - buffer, coords.z), tile2Lon(coords.x + 1 + buffer, coords.z));
    return LatLngBounds(sw, ne);
  }

  /// converts tile y to latitude. if the latitude is out of range it is adjusted to the min/max
  /// latitude (-90,90)
  static double tile2Lat(num y, num z) {
    var yBounded = math.max(y, 0);
    var n = math.pow(2.0, z);
    var latRad = math.atan(_sinh(math.pi * (1 - 2 * yBounded / n)));
    var latDeg = latRad * 180 / math.pi;
    //keep the point in the world
    return latDeg > 0 ? math.min(latDeg, 90).toDouble() : math.max(latDeg, -90).toDouble();
  }

  /// converts the tile x to longitude. if the longitude is out of range then it is adjusted to the
  /// min/max longitude (-180/180)
  static double tile2Lon(num x, num z) {
    var xBounded = math.max(x, 0);
    var lonDeg = xBounded / math.pow(2.0, z) * 360 - 180;
    return lonDeg > 0 ? math.min(lonDeg, 180).toDouble() : math.max(lonDeg, -180).toDouble();
  }

  /// hyperbolic sine implementation
  static double _sinh(double angle) {
    return (math.exp(angle) - math.exp(-angle)) / 2;
  }
}
