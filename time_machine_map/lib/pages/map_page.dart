import 'package:image_preview/image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_map/controllers/pictures_controller.dart';
import 'package:time_machine_map/molecules/map_popup.dart';
import 'package:time_machine_map/molecules/map_search_bar.dart';
import 'package:time_machine_net/time_machine_net.dart';
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

  @override
  void initState() {
    _picturesController = PicturesController(
      mapController: _mapController,
      networkService: context.read<NetworkService>(),
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
            heroTag: "btn1",
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
            heroTag: "btn2",
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
            heroTag: "btn3",
            onPressed: () async {

            },
            child: Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return PopupScope(
      popupController: _popupController,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          onTap: (_, __) {
            _popupController.hideAllPopups();
          }, // Hide popup when the map is tapped.
        ),
        children: [
          TileLayer( // Display map tiles from any source
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', // OSMF's Tile Server
            userAgentPackageName: 'com.example.app',
            // And many more recommended properties!
          ),
          _buildMarkers(),
          const MapCompass.cupertino(
            hideIfRotatedNorth: true,
            padding: EdgeInsets.fromLTRB(8, 60, 8, 8),
          ),
          _buildButtons(),
          _buildSearchBar(),
          RichAttributionWidget( // Include a stylish prebuilt attribution widget that meets all requirments
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')), // (external)
              ),
              // Also add images...
            ],
          ),
        ],
      ),
    );
  }

  Marker _buildMarker(Picture picture) {
    final bearing = picture.bearing;
    return Marker(
      key: ValueKey(picture.id),
      point: LatLng(picture.location.lat, picture.location.lng),
      width: 40,
      height: 40,
      child: Transform.rotate(
        angle: bearing == null ? 0 : bearing * pi / 180,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withAlpha(128),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Icon(Icons.arrow_upward),
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
            onClusterTap: (node) {
              final keys = Set<Key>.from(node.markers.map((e) => e.key));
              final pictures = snapshot.data?.where((e) => keys.contains(ValueKey(e.id))).toList();
              _showImages(pictures ?? []);
            },
            popupOptions: PopupOptions(
              popupController: _popupController,
              popupBuilder: (context, marker) {
                final picture = snapshot.data?.where((e) => ValueKey(e.id) == marker.key).firstOrNull;
                return MapPopup(
                  model: picture,
                  onShowImage: () => _showImage(picture),
                );
              },
            ),
            builder: (context, markers) {
              return Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.blue.withAlpha(128),
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: Text(
                  markers.length > 99 ? "99+" : markers.length.toString(),
                  style: const TextStyle(color: Colors.white),
                ),
              );
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

  void _showImage(Picture? model) {
    if (model == null) {
      return;
    }
    openImagePage(
      Navigator.of(context),
      imgUrl: model.url,
    );
  }

  void _showImages(List<Picture> models) {
    if (models.isEmpty) {
      return;
    }
    openImagesPage(
      Navigator.of(context),
      imgUrls: List.generate(models.length, (idx) => models[idx].url),
    );
  }
}
