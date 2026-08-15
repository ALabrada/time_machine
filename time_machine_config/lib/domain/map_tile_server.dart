import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final class MapTileServer {
  static var values = <MapTileServer>[
    MapTileServer(
      id: 'OpenStreetMap',
      url: (_) => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attributionLabel: (_) => "OpenStreetMap contributors",
      attributionUrl: (_) => 'https://openstreetmap.org/copyright',
    ),
    MapTileServer(
      id: 'ÖPNVKarte',
      url: (_) => 'https://tile.memomaps.de/tilegen/{z}/{x}/{y}.png',
      attributionLabel: (_) => "OpenStreetMap contributors",
      attributionUrl: (_) => 'https://openstreetmap.org/copyright',
    ),
    MapTileServer(
      id: 'Google Maps',
      url: (_) => 'http://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
      subdomains: ['mt0','mt1','mt2','mt3'],
      attributionLogo: (_) => 'assets/images/google_logo.png',
      attributionUrl: (_) => 'https://www.google.com/maps/',
    ),
    MapTileServer(
      id: 'Yandex Maps',
      url: (_) => 'https://core-renderer-tiles.maps.yandex.net/tiles?l=map&z={z}&x={x}&y={y}&scale=2&projection=web_mercator&lang=ru_RU',
      attributionLogo: (context) => Intl.systemLocale.startsWith('ru')
          ? 'assets/images/yndex_logo_ru.png'
          : 'assets/images/yndex_logo_en.png',
      attributionUrl: (_) => 'https://yandex.com/maps',
    ),
    MapTileServer(
      id: '2ГИС',
      url: (_) => 'http://tile2.maps.2gis.com/tiles?x={x}&y={y}&z={z}',
      attributionLogo: (_) => 'assets/images/2gis_logo.png',
      attributionUrl: (_) => 'https://law.2gis.ru/privacy',
    ),
    MapTileServer(
      id: 'VK Maps',
      url: (context) => Theme.of(context).brightness == Brightness.dark ? 'mmr://api/styles/dark_style.json' : 'mmr://api/styles/main_style.json',
      format: TileFormat.vector,
      attributionLogo: (_) => 'assets/images/vk_logo.png',
      attributionUrl: (_) => 'https://help.mail.ru/legal/terms/common/ua/',
    ),
  ];

  const MapTileServer({
    required this.id,
    required this.url,
    this.format=TileFormat.image,
    this.subdomains,
    this.attributionLogo,
    this.attributionLabel,
    this.attributionUrl,
  });

  final String id;
  final String Function(BuildContext) url;
  final TileFormat format;
  final List<String>? subdomains;
  final String Function(BuildContext)? attributionLogo;
  final String Function(BuildContext)? attributionLabel;
  final String Function(BuildContext)? attributionUrl;
}

enum TileFormat {
  image,
  vector
}