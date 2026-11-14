import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response okResponse(Object data) =>
    Response.ok(json.encode(data), headers: jsonHeaders);

Response jsonError(int statusCode, String message) => Response(
  statusCode,
  body: json.encode({'error': message}),
  headers: jsonHeaders,
);

/// Reads the request body into bytes, rejecting it as soon as it exceeds
/// [maxBodyBytes] (or as soon as the declared `Content-Length` does). The limit
/// is enforced while streaming, so an oversized body is never buffered in full.
Future<List<int>> readBodyBytes(Request request, int maxBodyBytes) async {
  final declared = request.contentLength;
  if (declared != null && declared > maxBodyBytes) {
    throw const FormatException('Request body too large');
  }
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in request.read()) {
    total += chunk.length;
    if (total > maxBodyBytes) {
      throw const FormatException('Request body too large');
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<String> readBody(Request request, int maxBodyBytes) async =>
    utf8.decode(await readBodyBytes(request, maxBodyBytes));

Map<String, dynamic> decodeJsonBody(String? body) {
  if (body == null || body.isEmpty) {
    throw const FormatException('Empty request body');
  }
  final decoded = json.decode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object');
  }
  return decoded;
}

DateTime? parseDate(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value.toString());
}
