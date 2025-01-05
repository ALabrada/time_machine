import 'package:animated_transform/animated_transform.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:time_machine_db/time_machine_db.dart';

class CompassView extends StatelessWidget {
  const CompassView({
    super.key,
    this.position,
    this.heading,
    this.target,
  });

  final Position? position;
  final double? heading;
  final Location? target;

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
          child: AnimatedTransform(
            rotate: bearing - currentHeading,
            child: Image.asset('assets/images/navigation.png',
              color: Colors.white,
              width: 100,
            ),
          ),
        ),
        Text('$distance m\n${currentHeading.round()} deg',
          style: TextStyle(color: Colors.red),
        ),
      ],
    );
  }
}
