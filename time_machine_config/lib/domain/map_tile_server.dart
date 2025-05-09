final class MapTileServer {
  static const values = <MapTileServer>[
    MapTileServer(
      id: 'OpenStreetMap',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attributionLabel: "OpenStreetMap contributors",
      attributionUrl: 'https://openstreetmap.org/copyright',
    ),
    MapTileServer(
      id: 'ÖPNVKarte',
      url: 'https://tile.memomaps.de/tilegen/{z}/{x}/{y}.png',
      attributionLabel: "OpenStreetMap contributors",
      attributionUrl: 'https://openstreetmap.org/copyright',
    ),
    MapTileServer(
      id: 'Google Maps',
      url: 'http://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
      subdomains: ['mt0','mt1','mt2','mt3'],
      attributionLogo: 'assets/images/google_logo.png',
      attributionUrl: 'https://www.google.com/maps/',
    ),
    MapTileServer(
      id: 'Yandex Maps',
      url: 'https://core-renderer-tiles.maps.yandex.net/tiles?l=map&z={z}&x={x}&y={y}&scale=2&projection=web_mercator&lang=ru_RU',
      attributionLogo: 'assets/images/yndex_logo_ru.png',
      attributionUrl: 'https://yandex.com/maps',
    ),
    MapTileServer(
      id: '2ГИС',
      url: 'http://tile2.maps.2gis.com/tiles?x={x}&y={y}&z={z}',
      attributionLogo: 'assets/images/2gis_logo.png',
      attributionUrl: 'https://law.2gis.ru/privacy',
    ),
  ];

  const MapTileServer({
    required this.id,
    required this.url,
    this.subdomains,
    this.attributionLogo,
    this.attributionLabel,
    this.attributionUrl,
  });

  final String id;
  final String url;
  final List<String>? subdomains;
  final String? attributionLogo;
  final String? attributionLabel;
  final String? attributionUrl;
}