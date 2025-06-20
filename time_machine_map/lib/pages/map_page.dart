import 'dart:async';

import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_map/controllers/pictures_controller.dart';
import 'package:time_machine_map/l10n/map_localizations.dart';
import 'package:time_machine_map/molecules/map_search_bar.dart';
import 'package:time_machine_map/molecules/picture_marker_layer.dart';
import 'package:time_machine_map/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
          onPressed: () => unawaited(_picturesController.moveToCurrentLocation()),
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
            _popupController.hideAllPopups();
          }, // Hide popup when the map is tapped.
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
    final title = model.description;
    final site = model.site;
    await showAdaptiveActionSheet<Picture>(
      context: context,
      title: title == null ? null : Text(title),
      cancelAction: CancelAction(
        title: Text(MapLocalizations.of(context).menuActionCancel),
      ),
      actions: [

        BottomSheetAction(
          leading: Icon(Icons.open_in_full),
          title: Text(MapLocalizations.of(context).menuActionView),
          onPressed: (context) {
            _showImage(model);
            context.pop();
          },
        ),
        BottomSheetAction(
          leading: Icon(Icons.photo_library),
          title: Text(MapLocalizations.of(context).menuActionImport),
          onPressed: (context) {
            _importPicture(model);
            context.pop();
          },
        ),
        BottomSheetAction(
          leading: Icon(Icons.camera_alt),
          title: Text(MapLocalizations.of(context).menuActionCamera),
          onPressed: (context) {
            _takePicture(model);
            context.pop();
          },
        ),
        if (site != null && site.isNotEmpty)
          BottomSheetAction(
            leading: Icon(Icons.open_in_browser),
            title: Text(MapLocalizations.of(context).menuActionOpenSource),
            onPressed: (context) {
              _openSite(site);
              context.pop();
            },
          ),
        BottomSheetAction(
          leading: Icon(Icons.share),
          title: Text(MapLocalizations.of(context).menuActionShare),
          onPressed: (context) {
            unawaited(_sharePicture(model));
            context.pop();
          },
        ),
      ],
    );
  }

  void _openAttribution() {
    final url = Uri.tryParse(_tileServer.attributionUrl?.call(context) ?? '');
    if (url != null) {
      unawaited(launchUrl(url));
    }
  }

  void _openSite(String site) {
    unawaited(launchUrlString(site));
  }

  void _importPicture(Picture picture) {
    context.go('/import?pictureId=${picture.id}');
  }

  Future<void> _sharePicture(Picture picture) async {
    final file = await CachedNetworkImageProvider.defaultCacheManager.getSingleFile(picture.url);
    await Share.shareXFiles([
      XFile(file.path),
    ], text: picture.text);
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
