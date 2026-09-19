import 'package:flutter_test/flutter_test.dart';
import 'package:listen_sharing_intent/listen_sharing_intent.dart';

import 'package:time_machine_img/services/sharing_service.dart';

void main() {
  const oauthScheme = 'com.fakegem.historylens';

  SharedMediaFile url(String path) => SharedMediaFile(path: path, type: SharedMediaType.url);
  SharedMediaFile image(String path) =>
      SharedMediaFile(path: path, type: SharedMediaType.image);

  test('oauth redirect URL is filtered out', () {
    final result = filterSharedMedia(
      [
        url('com.fakegem.historylens:/oauth2redirect?code=dummy&state=xyz'),
        url('https://legit.example/share'),
        image('/tmp/image.jpg'),
      ],
      {oauthScheme},
    );

    expect(result, hasLength(2));
    expect(result.first.path, 'https://legit.example/share');
    expect(result.last.path, '/tmp/image.jpg');
  });

  test('nothing filtered when ignore list is empty', () {
    final result = filterSharedMedia(
      [
        url('com.fakegem.historylens:/oauth2redirect?code=dummy&state=xyz'),
      ],
      {},
    );

    expect(result, hasLength(1));
  });

  test('empty input is a no-op', () {
    expect(filterSharedMedia(const [], {oauthScheme}), isEmpty);
  });
}