import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_map/controllers/pictures_controller.dart';
import 'package:time_machine_map/molecules/map_search_bar.dart';
import 'package:time_machine_map/molecules/picture_marker.dart';
import 'package:time_machine_map/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'package:url_launcher/url_launcher.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    this.stepZoom=1.0,
  });

  final double stepZoom;

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
    _picturesController.pictures.listen((_) => _popupController.hideAllPopups());
    super.initState();
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
      child: Stack(
        children: [
          _buildMap(),
        ],
      ),
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
          FloatingActionButton(
            heroTag: "my_location",
            onPressed: () => unawaited(_picturesController.moveToCurrentLocation()),
            child: Icon(Icons.my_location),
          ),
        ],
      ),
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
            _popupController.hideAllPopups();
          }, // Hide popup when the map is tapped.
        ),
        children: [
          TileLayer( // Display map tiles from any source
            urlTemplate: _tileServer.url, // OSMF's Tile Server
            userAgentPackageName: 'com.example.app',
            tileProvider: CancellableNetworkTileProvider(),
            subdomains: _tileServer.subdomains ?? const ['a', 'b', 'c'],
          ),
          CurrentLocationLayer(),
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

  Widget _buildCluster(List<Marker> markers) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: accent02.withAlpha(128),
        border: Border.all(color: label01, width: 1),
      ),
      child: Text(
        markers.length > 99 ? "99+" : markers.length.toString(),
        style: TextStyle(color: label01),
      ),
    );
  }

  Marker _buildMarker(Picture picture) {
    final bearing = picture.bearing;
    return PictureMarker(
      key: ValueKey('${picture.provider}/${picture.id}'),
      picture: picture,
      width: 30,
      height: 30,
      child: Transform.rotate(
        angle: bearing == null ? 0 : bearing * pi / 180,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: background02,
          ),
          child: Image.asset('assets/images/navigation.png',
            color: accent01,
          ),
        ),
      ),
    );
  }

  Widget _buildMarkers() {
    return StreamBuilder(
      stream: _picturesController.pictures,
      builder: (context, snapshot) {
        return MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            maxClusterRadius: 45,
            size: const Size(40, 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(50),
            markers: [
              for (final picture in snapshot.data ?? <Picture>[])
                _buildMarker(picture),
            ],
            centerMarkerOnClick: false,
            zoomToBoundsOnClick: false,
            popupOptions: PopupOptions(
              popupController: _popupController,
              popupBuilder: (context, marker) {
                final picture = marker is PictureMarker ? marker.picture : null;
                return Container(
                  margin: EdgeInsets.all(5),
                  constraints: BoxConstraints(maxWidth: 0.8 * MediaQuery.of(context).size.width),
                  child: PictureView.model(
                    model: picture,
                    onTapImage: picture == null ? null :() => _showImage(picture),
                  ),
                );
              },
            ),
            builder: (context, markers) {
              return _buildCluster(markers);
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return MapSearchBar(
      onSelected: _moveTo,
    );
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

  void _openAttribution() {
    final url = Uri.tryParse(_tileServer.attributionUrl?.call(context) ?? '');
    if (url != null) {
      launchUrl(url);
    }
  }

  Future<void> _takePicture(Picture model) async {
    final db = context.read<DatabaseService?>();
    final newModel = await db?.savePicture(model);
    final id = newModel?.localId;
    if (mounted && id != null) {
      context.go('/camera?pictureId=$id');
    }
  }
}
