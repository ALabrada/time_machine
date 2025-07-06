import 'dart:async';

import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:flutter_map_marker_cluster_plus/flutter_map_marker_cluster_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_map/controllers/pictures_controller.dart';
import 'package:time_machine_map/l10n/map_localizations.dart';
import 'package:time_machine_map/molecules/map_search_bar.dart';
import 'package:time_machine_map/molecules/picture_marker_layer.dart';
import 'package:time_machine_map/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/molecules/context_menu.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    this.stepZoom=1.0,
    this.pictureId,
  });

  final double stepZoom;
  final int? pictureId;

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  final _popupController = PopupController();
  late PicturesController _picturesController;

  MapTileServer get _tileServer => MapTileServer.values
      .where((e) => e.id == _picturesController.configurationService?.tileServer)
      .firstOrNull ?? MapTileServer.values[0];

  @override
  void initState() {
    _picturesController = PicturesController(
      configurationService: context.read<ConfigurationService>(),
      mapController: _mapController,
      networkService: context.read<NetworkService>(),
      preferences: context.read(),
    );
    super.initState();
    unawaited(_picturesController.show(
      pictureId: widget.pictureId,
      databaseService: context.read(),
    ));
  }

  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pictureId != widget.pictureId) {
      unawaited(_picturesController.show(
        pictureId: widget.pictureId,
        databaseService: context.read(),
      ));
    }
  }

  @override
  void dispose() {
    _picturesController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _buildMap(),
    );
  }

  Widget _buildButtons() {
    return PositionedDirectional(
      bottom: 60,
      end: 8,
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: "zoom_in",
            shape: const CircleBorder(),
            onPressed: () {
              _zoom(increment: widget.stepZoom);
            },
            child: Icon(
              Icons.zoom_in,
            ),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "zoom_out",
            shape: const CircleBorder(),
            onPressed: () {
              _zoom(increment: -widget.stepZoom);
            },
            child: Icon(
              Icons.zoom_out,
            ),
          ),
          const SizedBox(height: 22),
          _buildLocationButton(),
        ],
      ),
    );
  }

  Widget _buildLocationButton() {
    return StreamBuilder(
      stream: _picturesController.isProcessing,
      initialData: false,
      builder: (context, snapshot) {
        if (snapshot.requireData) {
          return Container(
            alignment: Alignment.center,
            height: 56,
            width: 56,
            child: CircularProgressIndicator(),
          );
        }
        return FloatingActionButton(
          heroTag: "my_location",
          onPressed: () async {
            unawaited(_findMyLocation());
          },
          child: Icon(Icons.my_location),
        );
      },
    );
  }

  Widget _buildMap() {
    final attributionLabel = _tileServer.attributionLabel?.call(context);
    final attributionLogo = _tileServer.attributionLogo?.call(context);
    return PopupScope(
      popupController: _popupController,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _picturesController.defaultCenter ?? LatLng(0, 0),
          initialZoom: _picturesController.defaultZoom ?? 2.0,
          initialRotation: _picturesController.defaultRotation ?? 0.0,
          onTap: (_, __) {
            _picturesController.clearSelection();
          }, // Hide popup when the map is tapped.
          onMapReady: () {
            _picturesController.mapReady.value = true;
          }
        ),
        children: [
          TileLayer( // Display map tiles from any source
            urlTemplate: _tileServer.url, // OSMF's Tile Server
            userAgentPackageName: _picturesController.networkService?.userAgent ?? 'com.example.app',
            tileProvider: CancellableNetworkTileProvider(),
            subdomains: _tileServer.subdomains ?? const ['a', 'b', 'c'],
          ),
          CurrentLocationLayer(
            positionStream: LocationMarkerDataStreamFactory()
                .fromGeolocatorPositionStream(stream: _picturesController.position),
          ),
          _buildMarkers(),
          const MapCompass.cupertino(
            hideIfRotatedNorth: true,
            padding: EdgeInsets.fromLTRB(8, 60, 8, 8),
          ),
          _buildButtons(),
          _buildSearchBar(),
          if (attributionLabel != null || attributionLogo != null)
            RichAttributionWidget(
              attributions: [
                if (attributionLogo != null)
                  LogoSourceAttribution(
                    Image.asset(attributionLogo),
                    onTap: _openAttribution,
                  ),
                if (attributionLabel != null)
                  TextSourceAttribution(
                    attributionLabel,
                    onTap: _openAttribution,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMarkers() {
    return StreamBuilder(
      stream: _picturesController.pictures,
      builder: (context, snapshot) {
        return PictureMarkerLayer(
          pictures: snapshot.data,
          selection: _picturesController.selection,
          popupController: _popupController,
          onSelected: _picturesController.select,
          onTap: (picture) => _showImage(picture),
          onLongPress: (picture) => unawaited(_showMenu(picture)),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return MapSearchBar(
      onSelected: _moveTo,
    );
  }

  Future<void> _findMyLocation() async {
    if (await _picturesController.moveToCurrentLocation()) {
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(MapLocalizations.of(context).locationNotFoundError),
      action: SnackBarAction(
        label: MapLocalizations.of(context).locationNotFoundAction,
        onPressed: () {
          if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            unawaited(Geolocator.openAppSettings());
          } else {
            unawaited(Geolocator.openLocationSettings());
          }
        },
      ),
    ));
  }

  void _moveTo(LatLng position) {
    _mapController.move(position, _mapController.camera.zoom);
  }

  void _zoom({
    double? value,
    double increment=0.0,
  }) {
    final position = _mapController.camera.center;
    final actualValue = value ?? _mapController.camera.zoom;
    _mapController.move(position, actualValue + increment);
  }

  void _showImage(Picture model) async {
    final db = context.read<DatabaseService?>();
    final newModel = await db?.savePicture(model);
    final id = newModel?.localId;
    if (mounted && id != null) {
      context.go('/picture/$id');
    }
  }

  Future<void> _showMenu(Picture model) async {
    await context.showContextMenu(
        model: model,
        databaseService: context.read(),
        navigateTo: (url) {
          if (!url.startsWith('/')) {
            launchUrlString(url);
          } else if (mounted) {
            context.go(url);
          }
        },
        shareFile: (path) {
          Share.shareXFiles([
            XFile(path),
          ], text: model.text);
        }
    );
  }

  void _openAttribution() {
    final url = Uri.tryParse(_tileServer.attributionUrl?.call(context) ?? '');
    if (url != null) {
      unawaited(launchUrl(url));
    }
  }
}
