import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_cam/time_machine_cam.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_map/time_machine_map.dart';
import 'package:time_machine_res/time_machine_res.dart';

import '../app.dart';
import '../generated/l10n.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
  });

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late RouteObserver _routeObserver;
  late StreamSubscription _importSubscription;
  int currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _importSubscription = context.read<SharingService>().imported
      .listen((v) => _onImported(success: v));
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
        indicatorColor: Theme.of(context).primaryColor,
        backgroundColor: background02,
        selectedIndex: currentPageIndex,
        destinations: <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.photo_album),
            icon: Icon(Icons.photo_album_outlined),
            label: S.of(context).homeTabsGallery,
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.camera_alt),
            icon: Icon(Icons.camera_alt_outlined),
            label: S.of(context).homeTabsCamera,
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.map),
            icon: Icon(Icons.map_outlined),
            label: S.of(context).homeTabsMap,
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings_outlined),
            label: S.of(context).homeTabsConfig,
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

  void _onImported({bool success=false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? ImgLocalizations.of(context).importSuccessful
          : ImgLocalizations.of(context).importError,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.primary,
    ));
  }
}
