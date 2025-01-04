import 'dart:async';

import 'package:ar_flutter_plugin_engine/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_engine/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_engine/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_engine/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_engine/managers/ar_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:time_machine_cam/controllers/ar_controller.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_net/time_machine_net.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.db,
    this.net,
  });

  final DatabaseService? db;
  final NetworkService? net;

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late ARController arController;

  @override
  void initState() {
    arController = ARController(
      databaseService: widget.db,
      networkService: widget.net,
    );
    super.initState();
  }

  @override
  void dispose() {
    arController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ARView(
      onARViewCreated: onARViewCreated,
    );
  }

  void onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) {
    unawaited(arController.initialize(
      arSessionManager: arSessionManager,
      arObjectManager: arObjectManager,
      arLocationManager: arLocationManager,
    ));
  }
}
