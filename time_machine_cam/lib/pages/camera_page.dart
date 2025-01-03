import 'package:flutter/material.dart';
import 'package:time_machine_net/time_machine_net.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.net,
  });

  final NetworkService? net;

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
