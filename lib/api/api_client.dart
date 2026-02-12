// lib/api/api_client.dart
//
// ✅ FIXED: ใช้ AuthStorage เป็นแหล่ง token เดียวกับ AuthApi
// - กันปัญหา login แล้ว API อื่นไม่เห็น token (เพราะ key คนละตัว)
// - เพิ่ม timeout กัน request ค้างจน UI spin นาน
//
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:clinic_payroll/services/auth_storage.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  // ===== Core request =====
  Uri _uri(String path, [Map<String, String>? query]) {
    final base =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (auth) {
      final token = await AuthStorage.getToken();
      if (token != null && token.isNotEmpty && token != 'null') {
        h['Authorization'] = 'Bearer $token';
      }
    }
    return h;
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    } catch (_) {
      return {'raw': body};
    }
  }

  Exception _httpError(int code, String body) {
    final m = _decodeJson(body);
    final msg = (m['message'] ?? m['error'] ?? 'HTTP $code').toString();
    return Exception('API Error ($code): $msg');
  }

  Future<Map<String, dynamic>> get(
    String path, {
    bool auth = true,
    Map<String, String>? query,
  }) async {
    final res = await http
        .get(
          _uri(path, query),
          headers: await _headers(auth: auth),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _decodeJson(res.body);
    }
    throw _httpError(res.statusCode, res.body);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final res = await http
        .post(
          _uri(path, query),
          headers: await _headers(auth: auth),
          body: json.encode(body ?? {}),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _decodeJson(res.body);
    }
    throw _httpError(res.statusCode, res.body);
  }
}
