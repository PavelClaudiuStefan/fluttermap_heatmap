import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:flutter_map_heatmap/src/custom_tile_layer.dart';
import 'package:flutter_map_heatmap/src/plugin/heat_map_tiles_provider_v2.dart';
import 'package:flutter_map_heatmap/src/plugin/heatmap_utils.dart';
import 'package:isolate_manager/isolate_manager.dart';

class HeatMapLayer extends StatefulWidget {
  final HeatMapOptions heatMapOptions;
  final HeatMapDataSource heatMapDataSource;
  final Stream<void>? reset;
  final TileDisplay tileDisplay;
  final TileUpdateTransformer? tileUpdateTransformer;
  final double maxZoom;

  HeatMapLayer(
      {super.key,
      HeatMapOptions? heatMapOptions,
      required this.heatMapDataSource,
      List<WeightedLatLng>? initialData,
      this.reset,
      this.tileDisplay = const TileDisplay.fadeIn(),
      this.tileUpdateTransformer,
      this.maxZoom = 18.0})
      : heatMapOptions = heatMapOptions ?? HeatMapOptions();

  @override
  State<StatefulWidget> createState() {
    return _HeatMapLayerState();
  }
}

class _HeatMapLayerState extends State<HeatMapLayer> {
  StreamSubscription<void>? _resetSub;

  /// As the reset stream no longer requests the new tile layers, only clears the
  /// cache, a pseudoUrl is generated every time a reset is requested
  late String pseudoUrl;

  late final IsolateManager<List<DataPoint>, DataFilteringParams> _filterDataIsolateManager = IsolateManager.create(
    HeatMapTilesUtils.filterData,
    workerName: 'HeatMapTilesUtils.filterData',
    concurrent: 2,
  );

  @override
  void initState() {
    _regenerateUrl();

    if (widget.reset != null) {
      _resetSub = widget.reset?.listen((event) {
        setState(() {
          _regenerateUrl();
        });
      });
    }
    super.initState();
  }

  @override
  void dispose() {
    _resetSub?.cancel();
    super.dispose();
  }

  void _regenerateUrl() {
    pseudoUrl = DateTime.now().microsecondsSinceEpoch.toString();
  }

  @override
  Widget build(BuildContext context) {

    // Custom tile layer
    return Opacity(
      opacity: widget.heatMapOptions.layerOpacity,
      child: CustomTileLayer(
        tileDimension: 256,
        maxZoom: widget.maxZoom,
        urlTemplate: pseudoUrl,
        tileDisplay: widget.tileDisplay,
        tileUpdateTransformer: widget.tileUpdateTransformer,
        tileProvider: HeatMapTilesProviderV2(
          filterDataIsolateManager: _filterDataIsolateManager,
          heatMapOptions: widget.heatMapOptions,
          dataSource: widget.heatMapDataSource,
        ),
      ),
    );

    // Custom tile provider
    return Opacity(
      opacity: widget.heatMapOptions.layerOpacity,
      child: TileLayer(
        tileDimension: 256,
        maxZoom: widget.maxZoom,
        urlTemplate: pseudoUrl,
        tileDisplay: widget.tileDisplay,
        tileUpdateTransformer: widget.tileUpdateTransformer,
        tileProvider: HeatMapTilesProviderV2(
          filterDataIsolateManager: _filterDataIsolateManager,
          heatMapOptions: widget.heatMapOptions,
          dataSource: widget.heatMapDataSource,
        ),
      ),
    );

    return Opacity(
      opacity: widget.heatMapOptions.layerOpacity,
      child: TileLayer(
        tileDimension: 256,
        maxZoom: widget.maxZoom,
        urlTemplate: pseudoUrl,
        tileDisplay: widget.tileDisplay,
        tileUpdateTransformer: widget.tileUpdateTransformer,
        tileProvider: HeatMapTilesProvider(
          heatMapOptions: widget.heatMapOptions,
          dataSource: widget.heatMapDataSource,
        ),
      ),
    );
  }
}
