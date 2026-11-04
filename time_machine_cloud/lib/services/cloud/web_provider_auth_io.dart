import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'provider_auth.dart';

class WebProviderSession implements ProviderSession {
  WebProviderSession({
    required this.accountId,
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  @override final String accountId;
  final DateTime expiresAt;

  @override bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override Map<String, String> get headers => {
        'Authorization': 'Bearer $accessToken',
      };
}

class WebProviderAuth implements ProviderAuth {
  WebProviderAuth({
    required this.providerId,
    required this.backendUrl,
    required this.webAppCallbackUrl,
  });

  final String providerId;
  final Uri backendUrl;
  final String webAppCallbackUrl;

  @override
  Future<ProviderSession?> restore() async => null;

  @override
  Future<ProviderSession> authenticate() async {
    throw UnsupportedError('Web auth only supported on web');
  }

  @override
  Future<void> clear() async {}
}
