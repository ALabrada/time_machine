import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:time_machine_map/molecules/picture_marker.dart';
import 'package:time_machine_res/time_machine_res.dart';
import 'package:time_machine_res/tokens/colors.dart';

class PictureMarkerLayer extends StatelessWidget {
  const PictureMarkerLayer({
    super.key,
    this.pictures,
    this.popupController,
    this.onTap,
    this.onLongPress,
  });

  final List<Picture>? pictures;
  final PopupController? popupController;
  final void Function(Picture model)? onTap;
  final void Function(Picture model)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 45,
        size: const Size(40, 40),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(50),
        markers: [
          for (final picture in pictures ?? <Picture>[])
            _buildMarker(picture),
        ],
        centerMarkerOnClick: false,
        zoomToBoundsOnClick: false,
        popupOptions: PopupOptions(
          popupController: popupController,
          popupBuilder: (context, marker) {
            final picture = marker is PictureMarker ? marker.picture : null;
            return Container(
              margin: EdgeInsets.all(5),
              constraints: BoxConstraints(maxWidth: 0.8 * MediaQuery.of(context).size.width),
              child: PictureView.model(
                model: picture,
                onLongPress: picture == null || onLongPress == null ? null : () => onLongPress!(picture),
                onTapImage: picture == null || onTap == null ? null : () => onTap!(picture),
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
}
