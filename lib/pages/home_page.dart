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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPageOrientations();
    });
    _importSubscription = context.read<SharingService>().imported
      .listen((v) => _onImported(success: v));
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _selectTab(widget.initialTab);
      _applyPageOrientations();
    }
  }

  @override
  void dispose() {
    _restorePageOrientations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentPageIndex < 0) {
      return Center(child: CircularProgressIndicator(),);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Theme.of(context).colorScheme.surface,
        systemNavigationBarColor: secondaryBackgroundColor(context),
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (!isTabletLayout(context)) {
              return _buildNavigationBarLayout();
            }
            return _buildNavigationRailLayout();
          },
        ),
      ),
    );
  }

  List<Widget> _buildDestinations() {
    return <Widget>[
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
    ];
  }

  List<NavigationRailDestination> _buildRailDestinations() {
    return <NavigationRailDestination>[
      NavigationRailDestination(
        selectedIcon: Icon(Icons.photo_album),
        icon: Icon(Icons.photo_album_outlined),
        label: Text(AppLocalizations.of(context).homeTabsGallery),
      ),
      NavigationRailDestination(
        selectedIcon: Icon(Icons.radar),
        icon: Icon(Icons.radar_outlined),
        label: Text(AppLocalizations.of(context).homeTabsCamera),
      ),
      NavigationRailDestination(
        selectedIcon: Icon(Icons.map),
        icon: Icon(Icons.map_outlined),
        label: Text(AppLocalizations.of(context).homeTabsMap),
      ),
      NavigationRailDestination(
        selectedIcon: Icon(Icons.settings),
        icon: Icon(Icons.settings_outlined),
        label: Text(AppLocalizations.of(context).homeTabsConfig),
      ),
    ];
  }

  void _selectPage(int index) {
    setState(() {
      currentPageIndex = index;
    });
    _applyPageOrientations();
  }

  void _applyPageOrientations() {
    // if (!isTabletLayout(context)) {
    //   return;
    // }
    // if (currentPageIndex == 1) {
    //   SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // } else {
    //   SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // }
  }

  void _restorePageOrientations() {
    // if (!isTabletLayout(context)) {
    //   return;
    // }
    // SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Widget _buildNavigationBarLayout() {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: _selectPage,
        indicatorColor: Theme.of(context).primaryColor,
        backgroundColor: secondaryBackgroundColor(context),
        selectedIndex: currentPageIndex,
        destinations: _buildDestinations(),
      ),
      body: _buildPage(),
    );
  }

  Widget _buildNavigationRailLayout() {
    final extendRail =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _buildRail(extended: extendRail),
            const VerticalDivider(
              thickness: 1,
              width: 1,
            ),
            Expanded(
              child: currentPageIndex == 1
                  ? ClipRect(child: _buildPage())
                  : _buildPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail({required bool extended}) {
    return NavigationRail(
      onDestinationSelected: _selectPage,
      selectedIndex: currentPageIndex,
      backgroundColor: secondaryBackgroundColor(context),
      indicatorColor: Theme.of(context).primaryColor,
      extended: extended,
      destinations: _buildRailDestinations(),
    );
  }

  Widget _buildPage() {
    return <Widget>[
      GalleryPage(),
      ScanningPage(),
      MapPage(
        pictureId: widget.pictureId,
      ),
      ConfigurationPage()
    ][currentPageIndex];
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
