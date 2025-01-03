import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_map/molecules/map_search_bar.dart';
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          _buildMap(),
          _buildButtons(),
          _buildSearchBar(),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return PositionedDirectional(
      bottom: 100,
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
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(),
      children: [
        TileLayer( // Display map tiles from any source
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', // OSMF's Tile Server
          userAgentPackageName: 'com.example.app',
          // And many more recommended properties!
        ),
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
}
