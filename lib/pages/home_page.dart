import 'dart:async';

import 'package:flutter/material.dart';
import 'package:time_machine_cam/time_machine_cam.dart';
import 'package:time_machine_db/services/database_service.dart';
import 'package:time_machine_map/time_machine_map.dart';
import 'package:time_machine_net/time_machine_net.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.net,
  });

  final NetworkService? net;

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late DatabaseService db;
  int currentPageIndex = -1;

  @override
  void initState() {
    super.initState();
    unawaited(onInitialize());
  }

  @override
  Widget build(BuildContext context) {
    if (currentPageIndex < 0) {
      return Center(child: CircularProgressIndicator(),);
    }
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        indicatorColor: Colors.amber,
        selectedIndex: currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.map),
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.camera_alt),
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Camera',
          ),
        ],
      ),
      body: <Widget>[
        MapPage(
          net: widget.net,
        ),
        CameraPage(
          db: db,
          net: widget.net,
        ),
      ][currentPageIndex],
    );
  }

  Future<void> onInitialize() async {
    db = await DatabaseService.load();
    setState(() {
      currentPageIndex = 0;
    });
  }
}
