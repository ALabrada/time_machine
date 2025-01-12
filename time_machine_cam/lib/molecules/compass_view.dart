import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:time_machine_db/time_machine_db.dart';

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
    if (position == null || target == null) {
      return SizedBox.shrink();
    }
    final currentHeading = heading ?? position.heading;
    final bearing = Geolocator.bearingBetween(position.latitude, position.longitude, target.lat, target.lng);
    final distance = Geolocator.distanceBetween(position.latitude, position.longitude, target.lat, target.lng).round();

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scaleY: 0.5,
          child: Transform.rotate(
            angle: (bearing - currentHeading) * math.pi / 180.0,
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
          Text(distance < 1000 ? '$distance m' : '+1 Km',
            style: TextTheme.of(context).bodyLarge?.merge(TextStyle(
                color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    );
  }
}
