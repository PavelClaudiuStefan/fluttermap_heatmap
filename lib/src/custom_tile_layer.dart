import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/layer/tile_layer/tile.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_bounds/tile_bounds.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_bounds/tile_bounds_at_zoom.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_image_manager.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_range.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_range_calculator.dart';
import 'package:flutter_map/src/layer/tile_layer/tile_scale_calculator.dart';
import 'package:flutter_map/src/misc/extensions.dart';

@immutable
class CustomTileLayer extends TileLayer {
  CustomTileLayer({
    // --- Parameters for your custom properties ---
    // Example:
    // required this.customParameter,

    // --- All parameters from the TileLayer constructor ---
    super.key,
    super.urlTemplate,
    super.fallbackUrl,
    // Note: super.tileSize is deprecated, so we call the super constructor
    // which handles the deprecation logic internally.
    // If you need to access it, you'd define it here and pass it,
    // but usually, you'd prefer `tileDimension`.
    @Deprecated('`tileSize` is deprecated. Use `tileDimension` instead.') double? tileSize, // We accept it to pass it to super if needed
    super.tileDimension,
    super.minZoom,
    super.maxZoom,
    super.minNativeZoom,
    super.maxNativeZoom,
    super.zoomReverse,
    super.zoomOffset,
    super.additionalOptions,
    super.subdomains,
    super.keepBuffer,
    super.panBuffer,
    super.errorImage,
    super.tileProvider,
    super.tms,
    super.wmsOptions,
    super.tileDisplay,
    bool? retinaMode, // Handled specially by super constructor logic
    super.errorTileCallback,
    super.tileBuilder,
    super.evictErrorTileStrategy,
    super.reset,
    super.tileBounds,
    super.tileUpdateTransformer,
    super.userAgentPackageName,
  });

  @override
  State<StatefulWidget> createState() => _CustomTileLayerState();
}

class _CustomTileLayerState extends State<CustomTileLayer> with TickerProviderStateMixin {
  bool _initializedFromMapCamera = false;

  final _tileImageManager = TileImageManager();
  late TileBounds _tileBounds;
  late TileRangeCalculator _tileRangeCalculator;
  late TileScaleCalculator _tileScaleCalculator;

  // We have to hold on to the mapController hashCode to determine whether we
  // need to reinitialize the listeners. didChangeDependencies is called on
  // every map movement and if we unsubscribe and resubscribe every time we
  // miss events.
  int? _mapControllerHashCode;

  StreamSubscription<TileUpdateEvent>? _tileUpdateSubscription;
  Timer? _pruneLater;

  MapEvent? _lastMapEvent;

  StreamSubscription<void>? _resetSub;

  // REMOVE once `tileSize` is removed, and replace references with
  // `widget.tileDimension`
  // ignore: deprecated_member_use_from_same_package
  int get _tileDimension => widget.tileSize?.toInt() ?? widget.tileDimension;

  @override
  void initState() {
    super.initState();
    _resetSub = widget.reset?.listen(_resetStreamHandler);
    _tileRangeCalculator = TileRangeCalculator(tileDimension: _tileDimension);
  }

  // This is called on every map movement so we should avoid expensive logic
  // where possible, or filter as necessary
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final camera = MapCamera.of(context);
    final mapController = MapController.of(context);

    _tileImageManager.setReplicatesWorldLongitude(
      camera.crs.replicatesWorldLongitude,
    );

    if (_mapControllerHashCode != mapController.hashCode) {
      _tileUpdateSubscription?.cancel();

      _mapControllerHashCode = mapController.hashCode;
      _tileUpdateSubscription = mapController.mapEventStream
          .map((mapEvent) => TileUpdateEvent(mapEvent: mapEvent))
          .transform(widget.tileUpdateTransformer)
          .listen(_onTileUpdateEvent);
    }

    var reloadTiles = false;
    if (!_initializedFromMapCamera || _tileBounds.shouldReplace(camera.crs, _tileDimension, widget.tileBounds)) {
      reloadTiles = true;
      _tileBounds = TileBounds(
        crs: camera.crs,
        tileDimension: _tileDimension,
        latLngBounds: widget.tileBounds,
      );
    }

    if (!_initializedFromMapCamera || _tileScaleCalculator.shouldReplace(camera.crs, _tileDimension)) {
      reloadTiles = true;
      _tileScaleCalculator = TileScaleCalculator(
        crs: camera.crs,
        tileDimension: _tileDimension,
      );
    }

    if (reloadTiles) _loadAndPruneInVisibleBounds(camera);

    _initializedFromMapCamera = true;
  }

  // @override
  // void didUpdateWidget(CustomTileLayer oldWidget) {
  //   super.didUpdateWidget(oldWidget);
  //   var reloadTiles = false;
  //
  //   // There is no caching in TileRangeCalculator so we can just replace it.
  //   _tileRangeCalculator = TileRangeCalculator(tileDimension: _tileDimension);
  //
  //   if (_tileBounds.shouldReplace(
  //       _tileBounds.crs, _tileDimension, widget.tileBounds)) {
  //     _tileBounds = TileBounds(
  //       crs: _tileBounds.crs,
  //       tileDimension: _tileDimension,
  //       latLngBounds: widget.tileBounds,
  //     );
  //     reloadTiles = true;
  //   }
  //
  //   if (_tileScaleCalculator.shouldReplace(
  //     _tileScaleCalculator.crs,
  //     _tileDimension,
  //   )) {
  //     _tileScaleCalculator = TileScaleCalculator(
  //       crs: _tileScaleCalculator.crs,
  //       tileDimension: widget.tileDimension,
  //     );
  //   }
  //
  //   if (oldWidget.resolvedRetinaMode != widget.resolvedRetinaMode) {
  //     reloadTiles = true;
  //   }
  //
  //   if (oldWidget.minZoom != widget.minZoom ||
  //       oldWidget.maxZoom != widget.maxZoom) {
  //     reloadTiles |=
  //     !_tileImageManager.allWithinZoom(widget.minZoom, widget.maxZoom);
  //   }
  //
  //   if (!reloadTiles) {
  //     final oldUrl =
  //         oldWidget.wmsOptions?._encodedBaseUrl ?? oldWidget.urlTemplate;
  //     final newUrl = widget.wmsOptions?._encodedBaseUrl ?? widget.urlTemplate;
  //
  //     final oldOptions = oldWidget.additionalOptions;
  //     final newOptions = widget.additionalOptions;
  //
  //     if (oldUrl != newUrl ||
  //         !(const MapEquality<String, String>())
  //             .equals(oldOptions, newOptions)) {
  //       _tileImageManager.reloadImages(widget, _tileBounds);
  //     }
  //   }
  //
  //   if (reloadTiles) {
  //     _tileImageManager.removeAll(widget.evictErrorTileStrategy);
  //     _loadAndPruneInVisibleBounds(MapCamera.maybeOf(context)!);
  //   } else if (oldWidget.tileDisplay != widget.tileDisplay) {
  //     _tileImageManager.updateTileDisplay(widget.tileDisplay);
  //   }
  //
  //   if (widget.reset != oldWidget.reset) {
  //     _resetSub?.cancel();
  //     _resetSub = widget.reset?.listen(_resetStreamHandler);
  //   }
  // }

  @override
  void dispose() {
    _tileUpdateSubscription?.cancel();
    _tileImageManager.removeAll(widget.evictErrorTileStrategy);
    _resetSub?.cancel();
    _pruneLater?.cancel();
    widget.tileProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastMapEvent != null && !_isMapCameraIdle(_lastMapEvent!)) {
      return const SizedBox.shrink();

      final controller = MapController.of(context);
      return StreamBuilder(
        stream: controller.mapEventStream,
        builder: (
            ctx,
            eventSnap,
            ) {
          if (_lastMapEvent.runtimeType != eventSnap.data.runtimeType) {
            if (kDebugMode) {
              print('_lastMapEvent is not the same as eventSnap.data\n'
                  '_lastMapEvent.runtimeType: ${_lastMapEvent.runtimeType}\n'
                  'eventSnap.data.runtimeType: ${eventSnap.data.runtimeType}');
            }
          }

          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${eventSnap.data?.runtimeType},'),
                    Text('${_lastMapEvent?.runtimeType},'),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }



    final map = MapCamera.of(context);

    if (_outsideZoomLimits(map.zoom.round())) return const SizedBox.shrink();

    final tileZoom = _clampToNativeZoom(map.zoom);
    final tileBoundsAtZoom = _tileBounds.atZoom(tileZoom);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: map,
      tileZoom: tileZoom,
    );

    // For a given map event both this rebuild method and the tile
    // loading/pruning logic will be fired. Any TileImages which are not
    // rendered in a corresponding Tile after this build will not become
    // visible until the next build. Therefore, in case this build is executed
    // before the loading/updating, we must pre-create the missing TileImages
    // and add them to the widget tree so that when they are loaded they notify
    // the Tile and become visible. We don't need to prune here as any new tiles
    // will be pruned when the map event triggers tile loading.
    _tileImageManager.createMissingTiles(
      visibleTileRange,
      tileBoundsAtZoom,
      createTile: (coordinates) => _createTileImage(
        coordinates: coordinates,
        tileBoundsAtZoom: tileBoundsAtZoom,
        pruneAfterLoad: false,
      ),
    );

    _tileScaleCalculator.clearCacheUnlessZoomMatches(map.zoom);

    // Note: `renderTiles` filters out all tiles that are either off-screen or
    // tiles at non-target zoom levels that are would be completely covered by
    // tiles that are *ready* and at the target zoom level.
    // We're happy to do a bit of diligent work here, since tiles not rendered are
    // cycles saved later on in the render pipeline.
    final tiles = _tileImageManager
        .getTilesToRender(visibleRange: visibleTileRange)
        .map((tileRenderer) => Tile(
              // Must be an ObjectKey, not a ValueKey using the coordinates, in
              // case we remove and replace the TileImage with a different one.
              key: ObjectKey(tileRenderer),
              scaledTileDimension: _tileScaleCalculator.scaledTileDimension(
                map.zoom,
                tileRenderer.positionCoordinates.z,
              ),
              currentPixelOrigin: map.pixelOrigin,
              tileImage: tileRenderer.tileImage,
              positionCoordinates: tileRenderer.positionCoordinates,
              tileBuilder: widget.tileBuilder,
            ))
        .toList();

    // Sort in render order. In reverse:
    //   1. Tiles at the current zoom.
    //   2. Tiles at the current zoom +/- 1.
    //   3. Tiles at the current zoom +/- 2.
    //   4. ...etc
    int renderOrder(Tile a, Tile b) {
      final (za, zb) = (a.tileImage.coordinates.z, b.tileImage.coordinates.z);
      final cmp = (zb - tileZoom).abs().compareTo((za - tileZoom).abs());
      if (cmp == 0) {
        // When compare parent/child tiles of equal distance, prefer higher res images.
        return za.compareTo(zb);
      }
      return cmp;
    }

    return MobileLayerTransformer(
      child: Stack(children: tiles..sort(renderOrder)),
    );
  }

  TileImage _createTileImage({
    required TileCoordinates coordinates,
    required TileBoundsAtZoom tileBoundsAtZoom,
    required bool pruneAfterLoad,
  }) {
    final cancelLoading = Completer<void>();

    final imageProvider = widget.tileProvider.supportsCancelLoading
        ? widget.tileProvider.getImageWithCancelLoadingSupport(
            tileBoundsAtZoom.wrap(coordinates),
            widget,
            cancelLoading.future,
          )
        : widget.tileProvider.getImage(
            tileBoundsAtZoom.wrap(coordinates),
            widget,
          );

    return TileImage(
      vsync: this,
      coordinates: coordinates,
      imageProvider: imageProvider,
      onLoadError: _onTileLoadError,
      onLoadComplete: (coordinates) {
        if (pruneAfterLoad) _pruneIfAllTilesLoaded(coordinates);
      },
      tileDisplay: widget.tileDisplay,
      errorImage: widget.errorImage,
      cancelLoading: cancelLoading,
    );
  }

  /// Load and/or prune tiles according to the visible bounds of the [event]
  /// center/zoom, or the current center/zoom if not specified.
  void _onTileUpdateEvent(TileUpdateEvent event) {
    _lastMapEvent = event.mapEvent;

    if (_isMapCameraIdle(event.mapEvent)) {
      return;
    }

    final tileZoom = _clampToNativeZoom(event.zoom);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: event.camera,
      tileZoom: tileZoom,
      center: event.center,
      viewingZoom: event.zoom,
    );

    if (event.load && !_outsideZoomLimits(tileZoom)) {
      _loadTiles(visibleTileRange, pruneAfterLoad: event.prune);
    }

    if (event.prune) {
      _tileImageManager.evictAndPrune(
        visibleRange: visibleTileRange,
        pruneBuffer: widget.panBuffer + widget.keepBuffer,
        evictStrategy: widget.evictErrorTileStrategy,
      );
    }
  }

  bool _isMapCameraIdle(MapEvent mapEvent) {
    if (mapEvent is MapEventFlingAnimationEnd) {
      return mapEvent.source != MapEventSource.dragStart;
    }

    // MapEventFlingAnimationNotStarted -> camera animation is not starting, therefore map camera is idle
    if (mapEvent is MapEventFlingAnimationNotStarted) {
      return true;
    }

    if (mapEvent is MapEventDoubleTapZoomEnd) {
      return true;
    }

    return false;
  }

  /// Load new tiles in the visible bounds and prune those outside.
  void _loadAndPruneInVisibleBounds(MapCamera camera) {
    final tileZoom = _clampToNativeZoom(camera.zoom);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: camera,
      tileZoom: tileZoom,
    );

    if (!_outsideZoomLimits(tileZoom)) {
      _loadTiles(
        visibleTileRange,
        pruneAfterLoad: true,
      );
    }

    _tileImageManager.evictAndPrune(
      visibleRange: visibleTileRange,
      pruneBuffer: max(widget.panBuffer, widget.keepBuffer),
      evictStrategy: widget.evictErrorTileStrategy,
    );
  }

  // For all valid TileCoordinates in the [tileLoadRange], expanded by the
  // [TileLayer.panBuffer], this method will do the following depending on
  // whether a matching TileImage already exists or not:
  //   * Exists: Mark it as current and initiate image loading if it has not
  //     already been initiated.
  //   * Does not exist: Creates the TileImage (they are current when created)
  //     and initiates loading.
  //
  // Additionally, any current TileImages outside of the [tileLoadRange],
  // expanded by the [TileLayer.panBuffer] + [TileLayer.keepBuffer], are marked
  // as not current.
  void _loadTiles(
    DiscreteTileRange tileLoadRange, {
    required bool pruneAfterLoad,
  }) {
    final tileZoom = tileLoadRange.zoom;
    final expandedTileLoadRange = tileLoadRange.expand(widget.panBuffer);

    // Build the queue of tiles to load. Marks all tiles with valid coordinates
    // in the tileLoadRange as current.
    final tileBoundsAtZoom = _tileBounds.atZoom(tileZoom);
    final tilesToLoad = _tileImageManager.createMissingTiles(
      expandedTileLoadRange,
      tileBoundsAtZoom,
      createTile: (coordinates) => _createTileImage(
        coordinates: coordinates,
        tileBoundsAtZoom: tileBoundsAtZoom,
        pruneAfterLoad: pruneAfterLoad,
      ),
    );

    // Re-order the tiles by their distance to the center of the range.
    final tileCenter = expandedTileLoadRange.center;
    tilesToLoad.sort(
      (a, b) => (a.coordinates.toOffset() - tileCenter).distanceSquared.compareTo((b.coordinates.toOffset() - tileCenter).distanceSquared),
    );

    // Create the new Tiles.
    for (final tile in tilesToLoad) {
      tile.load();
    }
  }

  /// Rounds the zoom to the nearest int and clamps it to the native zoom limits
  /// if there are any.
  int _clampToNativeZoom(double zoom) => zoom.round().clamp(widget.minNativeZoom, widget.maxNativeZoom);

  void _onTileLoadError(TileImage tile, Object error, StackTrace? stackTrace) {
    debugPrint(error.toString());
    widget.errorTileCallback?.call(tile, error, stackTrace);
  }

  void _pruneIfAllTilesLoaded(TileCoordinates coordinates) {
    if (!_tileImageManager.containsTileAt(coordinates) || !_tileImageManager.allLoaded) {
      return;
    }

    widget.tileDisplay.when(instantaneous: (_) {
      _pruneWithCurrentCamera();
    }, fadeIn: (fadeIn) {
      // Wait a bit more than tileFadeInDuration to trigger a pruning so that
      // we don't see tile removal under a fading tile.
      _pruneLater?.cancel();
      _pruneLater = Timer(
        fadeIn.duration + const Duration(milliseconds: 50),
        _pruneWithCurrentCamera,
      );
    });
  }

  void _pruneWithCurrentCamera() {
    final camera = MapCamera.of(context);
    final visibleTileRange = _tileRangeCalculator.calculate(
      camera: camera,
      tileZoom: _clampToNativeZoom(camera.zoom),
      center: camera.center,
      viewingZoom: camera.zoom,
    );
    _tileImageManager.prune(
      visibleRange: visibleTileRange,
      pruneBuffer: max(widget.panBuffer, widget.keepBuffer),
      evictStrategy: widget.evictErrorTileStrategy,
    );
    setState(() {});
  }

  bool _outsideZoomLimits(num zoom) => zoom < widget.minZoom || zoom > widget.maxZoom;

  void _resetStreamHandler(void _) {
    _tileImageManager.removeAll(widget.evictErrorTileStrategy);
    if (mounted) _loadAndPruneInVisibleBounds(MapCamera.of(context));
  }
}
