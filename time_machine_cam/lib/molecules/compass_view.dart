import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:time_machine_db/time_machine_db.dart';
import 'package:ar_location_view/ar_location_view.dart';

import '../l10n/cam_localizations.dart';

class CompassView extends StatelessWidget {
  const CompassView({
    super.key,
    this.position,
    this.heading,
    this.target,
    this.minDistance=0,
  });

  final Position? position;
  final double? heading;
  final Location? target;
  final double minDistance;

  @override
  Widget build(BuildContext context) {
    final position = this.position;
    final target = this.target;
    final heading = this.heading;
    if (position == null || target == null || heading == null) {
      return SizedBox.shrink();
    }
    final azimuth = Geolocator.bearingBetween(position.latitude, position.longitude, target.lat, target.lng);
    final distance = Geolocator.distanceBetween(position.latitude, position.longitude, target.lat, target.lng).round();
    final delta = -ArMath.deltaAngle(heading, azimuth);

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scaleY: 0.5,
          child: Transform.rotate(
            angle: delta.toRadians,
            child: Container(
              width: 100,
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                color: Theme.of(context).colorScheme.surface.withAlpha(127),
              ),
              child: Image.asset('assets/images/navigation.png',
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ),
        if (distance >= minDistance)
          Text(distance < 1000
              ? CamLocalizations.of(context).distanceInMeters(distance)
              : CamLocalizations.of(context).distanceGreaterThan1Km,
            style: TextTheme.of(context).bodyLarge?.merge(TextStyle(
                color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    );
  }
}
