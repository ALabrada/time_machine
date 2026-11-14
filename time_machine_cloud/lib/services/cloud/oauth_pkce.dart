import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;

/// PKCE helpers shared by the Google, Yandex and Dropbox consent flows. All
/// three providers support the S256 challenge derived from a random code
/// verifier, so the Cloud clients can open an authorization URL and exchange
/// the resulting code without any client secret.
const _verifierCharacters =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// Generates the random 64-character PKCE code verifier.
String createPkceCodeVerifier() {
  final random = Random.secure();
  return List.generate(64, (_) {
    return _verifierCharacters[random.nextInt(_verifierCharacters.length)];
  }).join();
}

/// Computes the URL-safe (unpadded) S256 code challenge of [codeVerifier],
/// sent to the authorization endpoint as `code_challenge`.
String pkceCodeChallenge(String codeVerifier) {
  final digest = SHA256Digest().process(utf8.encode(codeVerifier));
  return base64Url.encode(digest).replaceAll('=', '');
}

/// Generates a random URL-safe token for the OAuth `state` parameter, which
/// binds an authorization redirect to the consent request that started it.
String randomOAuthState() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64Url.encode(Uint8List.fromList(bytes));
}