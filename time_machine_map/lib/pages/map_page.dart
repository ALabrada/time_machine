import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:time_machine_map/controllers/pictures_controller.dart';
import 'package:time_machine_map/molecules/map_search_bar.dart';
import 'package:time_machine_net/time_machine_net.dart';
import 'package:url_launcher/url_launcher.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    this.net,
    this.stepZoom=1.0,
  });

  final NetworkService? net;
  final double stepZoom;

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  late PicturesController _picturesController;

  @override
  void initState() {
    _picturesController = PicturesController(
      mapController: _mapController,
      networkService: widget.net,
    );
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
    return StreamBuilder(
      stream: _picturesController.pictures,
      builder: (context, snapshot) {
        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
              onMapReady: () {
              }
          ),
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
            MarkerLayer(
              markers: [
                for (final picture in snapshot.data ?? <Picture>[])
                  _buildMarker(picture),
              ],
            )
          ],
        );
      },
    );
  }

  Marker _buildMarker(Picture picture) {
    return Marker(
      point: LatLng(picture.location.lat, picture.location.lng),
      width: 64,
      height: 64,
      child: CachedNetworkImage(
        imageUrl: picture.previewUrl ?? picture.url,
        width: 64,
        height: 64,
      ),
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
