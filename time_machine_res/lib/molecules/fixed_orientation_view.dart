import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class FixedOrientationView extends StatefulWidget {
  const FixedOrientationView({
    super.key,
    this.orientations,
    required this.child,
  });

  final List<DeviceOrientation>? orientations;
  final Widget child;

  @override
  _FixedOrientationViewState createState() => _FixedOrientationViewState();
}

class _FixedOrientationViewState extends State<FixedOrientationView>  with RouteAware {
  late RouteObserver _routeObserver;

  @override
  void initState() {
    final orientations = widget.orientations;
    if (orientations != null) {
      print('Set orientations: $orientations');
      SystemChrome.setPreferredOrientations(orientations);
    }
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeObserver = context.read<RouteObserver>();
    _routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    _routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void didPush() {
  }

  @override
  void didPushNext() {
  }

  @override
  void didPop() {
  }

  @override
  void didPopNext() {
    final orientations = widget.orientations;
    if (orientations != null) {
      print('Set orientations: $orientations');
      SystemChrome.setPreferredOrientations(orientations);
    }
  }
}
