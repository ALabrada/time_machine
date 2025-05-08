import 'package:flutter/material.dart';
import 'package:time_machine_cam/time_machine_cam.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_map/time_machine_map.dart';
import 'package:time_machine_res/time_machine_res.dart';

import '../app.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
  });

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late RouteObserver _routeObserver;
  int currentPageIndex = 0;

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
        indicatorColor: Theme.of(context).primaryColor,
        backgroundColor: background02,
        selectedIndex: currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.photo_album),
            icon: Icon(Icons.photo_album_outlined),
            label: 'Gallery',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.camera_alt),
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Camera',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.map),
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
      body: <Widget>[
        GalleryPage(),
        ScanningPage(),
        MapPage(),
        ConfigurationPage()
      ][currentPageIndex],
    );
  }
}
