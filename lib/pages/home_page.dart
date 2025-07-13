import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:time_machine_cam/time_machine_cam.dart';
import 'package:time_machine_config/time_machine_config.dart';
import 'package:time_machine_img/time_machine_img.dart';
import 'package:time_machine_map/time_machine_map.dart';
import 'package:time_machine_res/time_machine_res.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialTab,
    this.pictureId,
  });

  final String? initialTab;
  final int? pictureId;

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
    _selectTab(widget.initialTab);
    _importSubscription = context.read<SharingService>().imported
      .listen((v) => _onImported(success: v));
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _selectTab(widget.initialTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentPageIndex < 0) {
      return Center(child: CircularProgressIndicator(),);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Theme.of(context).colorScheme.surface,
      ),
      child: Scaffold(
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
              label: AppLocalizations.of(context).homeTabsGallery,
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.radar),
              icon: Icon(Icons.radar_outlined),
              label: AppLocalizations.of(context).homeTabsCamera,
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.map),
              icon: Icon(Icons.map_outlined),
              label: AppLocalizations.of(context).homeTabsMap,
            ),
            NavigationDestination(
              selectedIcon: Icon(Icons.settings),
              icon: Icon(Icons.settings_outlined),
              label: AppLocalizations.of(context).homeTabsConfig,
            ),
          ],
        ),
        body: <Widget>[
          GalleryPage(),
          ScanningPage(),
          MapPage(
            pictureId: widget.pictureId,
          ),
          ConfigurationPage()
        ][currentPageIndex],
      ),
    );
  }

  void _selectTab(String? name) {
    if (name == null) {
      return;
    }
    setState(() {
      switch (name.toLowerCase()) {
        case "gallery": currentPageIndex = 0;
        case "nearby": currentPageIndex = 1;
        case "map": currentPageIndex = 2;
        case "settings": currentPageIndex = 3;
        default: break;
      }
    });
  }

  void _onImported({bool success=false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? ImgLocalizations.of(context).importSuccessful
          : ImgLocalizations.of(context).importError,
      ),
    ));
  }
}
