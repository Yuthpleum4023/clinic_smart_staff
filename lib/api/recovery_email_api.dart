import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';

class RecoveryEmailStatus {
  final bool ok;
  final bool hasEmail;
  final String emailMasked;
  final bool phoneOnly;

  const RecoveryEmailStatus({
    required this.ok,
    required this.hasEmail,
    required this.emailMasked,
    required this.phoneOnly,
  });

  factory RecoveryEmailStatus.fromMap(Map<String, dynamic> map) {
    return RecoveryEmailStatus(
      ok: map['ok'] == true,
      hasEmail: map['hasEmail'] == true,
      emailMasked: (map['emailMasked'] ?? '').toString().trim(),
      phoneOnly: map['phoneOnly'] == true,
    );
  }
}

class RecoveryEmailApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.authBaseUrl);

  static Future<RecoveryEmailStatus> status() async {
    final json = await _client.get('/users/me/recovery-email/status');
    return RecoveryEmailStatus.fromMap(json);
  }

  static Future<Map<String, dynamic>> requestOtp({
    required String email,
  }) async {
    return _client.post(
      '/users/me/recovery-email/request',
      body: {
        'email': email.trim(),
      },
    );
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String code,
  }) async {
    return _client.post(
      '/users/me/recovery-email/verify',
      body: {
        'email': email.trim(),
        'code': code.trim(),
      },
    );
  }
}
