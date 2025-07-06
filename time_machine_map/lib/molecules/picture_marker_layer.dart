import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster_plus/flutter_map_marker_cluster_plus.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_map/molecules/picture_marker.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'package:time_machine_res/tokens/colors.dart';

class PictureMarkerLayer extends StatefulWidget {
  const PictureMarkerLayer({
    super.key,
    this.pictures,
    this.selection,
    this.popupController,
    this.onSelected,
    this.onTap,
    this.onLongPress,
  });

  final List<Picture>? pictures;
  final Stream<Picture?>? selection;
  final PopupController? popupController;
  final void Function(Picture model)? onSelected;
  final void Function(Picture model)? onTap;
  final void Function(Picture model)? onLongPress;

  @override
  _PictureMarkerLayerState createState() => _PictureMarkerLayerState();
}

class _PictureMarkerLayerState extends State<PictureMarkerLayer> {
  late PopupController _popupController;
  StreamSubscription? _selectionSubscription;
  List<Marker> _markers = [];

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _popupController = widget.popupController ?? PopupController();
    _updateMarkers();
    _selectionSubscription = widget.selection?.listen((e) {
      _updateSelection(e);
    });
  }

  @override
  void didUpdateWidget(covariant PictureMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMarkers();
    _selectionSubscription?.cancel();
    _selectionSubscription = widget.selection?.listen((e) {
      _updateSelection(e);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 45,
        size: const Size(40, 40),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(50),
        markers: _markers,
        centerMarkerOnClick: false,
        zoomToBoundsOnClick: false,
        popupOptions: PopupOptions(
          popupController: _popupController,
          markerTapBehavior: MarkerTapBehavior.custom((spec, state, _) {
            final marker = spec.marker;
            if (marker is PictureMarker) {
              widget.onSelected?.call(marker.picture);
            }
          }),
          popupBuilder: (context, marker) {
            final picture = marker is PictureMarker ? marker.picture : null;
            return Container(
              margin: EdgeInsets.all(5),
              constraints: BoxConstraints(maxWidth: 0.8 * MediaQuery.of(context).size.width),
              child: PictureView.model(
                model: picture,
                onLongPress: picture == null || widget.onLongPress == null ? null : () => widget.onLongPress!(picture),
                onTapImage: picture == null || widget.onTap == null ? null : () => widget.onTap!(picture),
              ),
            );
          },
        ),
        builder: (context, markers) {
          return _buildCluster(markers);
        },
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
          clipBehavior: Clip.antiAlias,
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

  void _updateMarkers() {
    _markers = [
      for (final picture in widget.pictures ?? <Picture>[])
        _buildMarker(picture),
    ];
  }

  void _updateSelection(Picture? selection) {
    final selectedMarker = selection == null ? null : _markers.whereType<PictureMarker>().where((e) {
      return e.picture.provider == selection.provider && e.picture.id == selection.id;
    }).firstOrNull;
    if (selectedMarker == null) {
      _popupController.hideAllPopups();
    } else {
      _popupController.showPopupsOnlyFor([selectedMarker]);
    }
  }
}
