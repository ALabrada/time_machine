class VectorService {
  final String vkApiKey;

  VectorService({required this.vkApiKey, String? userAgent});

  void clearStyleCache() {}

  Future<dynamic> loadStyle(String uri) async {
    throw UnsupportedError('VK Maps vector tiles are not supported on the web');
  }
}