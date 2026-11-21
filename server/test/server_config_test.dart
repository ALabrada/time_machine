import 'dart:io';

import 'package:test/test.dart';
import 'package:time_machine_server/server_config.dart';

void main() {
  test('loads values from a JSON config file', () {
    final dir = Directory.systemTemp.createTempSync('server_config_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/config.json')
      ..writeAsStringSync('{"TEST_SERVER_CONFIG_VALUE":"from-file"}');

    final config = ServerConfig.load(path: file.path);

    expect(config['TEST_SERVER_CONFIG_VALUE'], 'from-file');
    expect(config['MISSING_VALUE'], '');
  });
}
