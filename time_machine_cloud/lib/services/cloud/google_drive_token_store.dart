

/// The session information needed to restore a Google Drive session across
/// app launches, without re-running the OAuth consent flow.
class GoogleDriveSession {
  const GoogleDriveSession({
    required this.refreshToken,
    required this.clientId,
    this.userEmail,
  });

  factory GoogleDriveSession.fromJson(Map<String, Object?> json) {
    return GoogleDriveSession(
      refreshToken: json['refreshToken']! as String,
      clientId: json['clientId']! as String,
      userEmail: json['userEmail'] as String?,
    );
  }

  /// OAuth 2 refresh token that keeps the access token fresh.
  final String refreshToken;

  /// Google Developer Console client identifier the token was issued for.
  final String clientId;

  /// The signed-in account, once known.
  final String? userEmail;

  Map<String, Object?> toJson() => {
        'refreshToken': refreshToken,
        'clientId': clientId,
        'userEmail': userEmail,
      };
}

/// Persists the Google Drive session across app launches so it can be
/// restored without re-running the OAuth consent flow.
abstract class GoogleDriveTokenStore {
  Future<GoogleDriveSession?> read();
  Future<void> write(GoogleDriveSession session);
  Future<void> clear();
}

