import 'package:animated_transform/animated_transform.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:time_machine_db/time_machine_db.dart';

class CompassView extends StatelessWidget {
  const CompassView({
    super.key,
    this.position,
    this.target,
  });

  final Position? position;
  final Location? target;

  @override
  Widget build(BuildContext context) {
    final position = this.position;
    final target = this.target;
    if (position == null || target == null) {
      return SizedBox.shrink();
    }

    final heading = Geolocator.bearingBetween(position.latitude, position.longitude, target.lat, target.lng);
    final distance = Geolocator.distanceBetween(position.latitude, position.longitude, target.lat, target.lng).round();

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scaleY: 0.5,
          child: AnimatedTransform(
            rotate: position.heading - heading,
            child: Image.asset('assets/images/navigation.png',
              color: Colors.white,
              width: 100,
            ),
          ),
        ),
        Text('$distance m\n$heading deg',
          style: TextStyle(color: Colors.red),
        ),
      ],
    );
  }
}
