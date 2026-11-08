import 'dart:convert';

import 'package:shelf/shelf.dart';

const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response okResponse(Object data) =>
    Response.ok(json.encode(data), headers: jsonHeaders);

Response jsonError(int statusCode, String message) => Response(
  statusCode,
  body: json.encode({'error': message}),
  headers: jsonHeaders,
);

Future<String> readBody(Request request, int maxBodyBytes) async {
  final bytes = await request.read().expand((chunk) => chunk).toList();
  final total = bytes.fold<int>(0, (sum, byte) => sum + byte);
  if (total > maxBodyBytes) {
    throw const FormatException('Request body too large');
  }
  return utf8.decode(bytes);
}

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
