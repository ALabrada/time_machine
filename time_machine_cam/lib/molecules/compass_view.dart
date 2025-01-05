import 'package:animated_transform/animated_transform.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:time_machine_net/time_machine_net.dart';

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

    final angle = Geolocator.bearingBetween(position.latitude, position.longitude, target.lat, target.lng);
    final distance = Geolocator.distanceBetween(position.latitude, position.longitude, target.lat, target.lng).round();

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scaleY: 0.75,
          child: AnimatedTransform(
            rotate: angle,
            child: Image.asset('assets/images/navigation.png',
              color: Colors.white,
              width: 100,
            ),
          ),
        ),
        Text('$distance m'),
      ],
    );
  }
}
