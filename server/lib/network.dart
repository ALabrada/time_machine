import 'package:time_machine_sources/services/geocoders/geonames_geocoder.dart';
import 'package:time_machine_sources/services/geocoders/osm_geocoder.dart';
import 'package:time_machine_sources/services/geocoders/vkmaps_geocoder.dart';
import 'package:time_machine_sources/services/geocoders/yandex_geocoder.dart';
import 'package:time_machine_sources/services/network_service.dart';
import 'package:time_machine_sources/services/providers/history_pin_provider.dart';
import 'package:time_machine_sources/services/providers/pastvu_provider.dart';
import 'package:time_machine_sources/services/providers/retro_photos_provider.dart';
import 'package:time_machine_sources/services/providers/russia_in_photo_provider.dart';
import 'package:time_machine_sources/services/providers/sepia_town_provider.dart';

/// Builds the shared [NetworkService] used by the proxy handlers.
///
/// Cloud backends are handled separately by the cloud API (cloud sync is a
/// native feature of the app), so they are not part of the network service.
NetworkService buildNetworkService({
  String? userAgent,
  String? vkMapsApiKey,
  String? yandexApiKey,
  String? geonamesUserName,
}) {
  final geocoders = <String, GeocodingService>{
    if (userAgent != null) 'OSM': OsmSearchEngine(userAgent: userAgent),
    'Geonames': GeonamesGeocoder(
      userAgent: userAgent,
      userName: geonamesUserName ?? 'historylens',
    ),
    if (vkMapsApiKey != null && vkMapsApiKey.isNotEmpty)
      'VKMaps': VKMapsGeocoder(userAgent: userAgent, apiKey: vkMapsApiKey),
    if (yandexApiKey != null && yandexApiKey.isNotEmpty)
      'Yandex': YandexGeocoder(userAgent: userAgent, apiKey: yandexApiKey),
  };
  final providers = <String, DataProvider>{
    'pastvu': PastVuProvider(userAgent: userAgent),
    'russiainphoto': RussiaInPhotoProvider(userAgent: userAgent),
    're.photos': RetroPhotosProvider(userAgent: userAgent),
    'historypin': HistoryPinProvider(userAgent: userAgent),
    'sepiatown': SepiaTownProvider(userAgent: userAgent),
  };
  return NetworkService(
    userAgent: userAgent,
    geocoders: geocoders,
    providers: providers,
  );
}

/// Default image hosts the proxy may forward `/api/image` requests to. The
/// app requests exactly these origins' CDN links.
const defaultAllowedImageHosts = [
  'pastvu.com',
  'www.pastvu.com',
  'www.historypin.org',
  'www.re.photos',
  'russiainphoto.ru',
  'www.sepiatown.com',
];
