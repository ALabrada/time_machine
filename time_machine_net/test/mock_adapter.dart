import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class MockDioAdapter implements HttpClientAdapter {
  Object? Function(RequestOptions options)? dataFor;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = dataFor?.call(options);
    if (data == null) {
      throw DioException(
        requestOptions: options,
        message: 'No mock handler for ${options.path}',
      );
    }
    final body = utf8.encode(jsonEncode(data));
    return ResponseBody(
      Stream.value(Uint8List.fromList(body)),
      200,
      headers: {'content-type': ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}
