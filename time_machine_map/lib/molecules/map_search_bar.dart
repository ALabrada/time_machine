import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_floating_search_bar_2/material_floating_search_bar_2.dart';
import 'package:time_machine_map/controllers/map_search_controller.dart';

class MapSearchBar extends StatefulWidget {
  const MapSearchBar({
    super.key,
    this.onSelected,
  });

  final ValueChanged<LatLng>? onSelected;

  @override
  _MapSearchBarState createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final _fieldController = FloatingSearchBarController();
  final _searchController = MapSearchController();

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return FloatingSearchBar(
      hint: 'Search...',
      controller: _fieldController,
      scrollPadding: const EdgeInsets.only(top: 16, bottom: 56),
      transitionDuration: const Duration(milliseconds: 800),
      transitionCurve: Curves.easeInOut,
      physics: const BouncingScrollPhysics(),
      axisAlignment: isPortrait ? 0.0 : -1.0,
      openAxisAlignment: 0.0,
      width: isPortrait ? 600 : 500,
      debounceDelay: const Duration(milliseconds: 500),
      onQueryChanged: (query) {
        unawaited(_searchController.locate(query));
      },
      // Specify a custom transition to be used for
      // animating between opened and closed stated.
      transition: CircularFloatingSearchBarTransition(),
      actions: [
        FloatingSearchBarAction.searchToClear(
          showIfClosed: false,
        ),
      ],
      builder: (context, transition) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Material(
            color: Colors.white,
            elevation: 4.0,
            child: _buildResults(),
          ),
        );
      },
    );
  }

  Widget _buildResults() {
    return StreamBuilder(
      stream: _searchController.results,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.isEmpty) {
          return SizedBox.shrink();
        }
        final tiles = data.map((e) => ListTile(
          title: Text(e.name),
          onTap: () {
            _fieldController.close();
            widget.onSelected?.call(LatLng(e.lat, e.lng));
          },
        ));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: ListTile.divideTiles(
            context: context,
            tiles: tiles,
          ).toList(),
        );
      },
    );
  }
}
