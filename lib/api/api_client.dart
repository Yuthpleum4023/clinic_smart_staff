// lib/api/api_client.dart
//
// ✅ FINAL — SINGLE SOURCE OF TRUTH FOR AUTH HEADER
// - sanitize token (trim / remove quotes / remove leading "Bearer " / reject null)
// - reject non-JWT token (ต้องมี 3 ส่วน a.b.c) กัน jwt malformed
// - Render-safe timeout (60s) กัน cold start
// - supports: GET / POST / PATCH / PUT / DELETE
//
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/services/auth_storage.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  static const Duration _timeout = Duration(seconds: 60);

  // ===== Core request =====
  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query);
  }

  // ===== Token sanitize =====
  String _cleanToken(String raw) {
    var t = raw.trim();

    // กันเคสเก็บมาเป็น "...." (มี quote ครอบ)
    if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
      t = t.substring(1, t.length - 1).trim();
    }

    // กันเคสเก็บมาเป็น Bearer xxx
    if (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }

    // กัน "null" / ว่าง
    if (t.isEmpty || t == 'null') return '';

    // กัน token ที่ไม่ใช่ JWT (ต้องมี 3 ส่วน)
    if (t.split('.').length != 3) return '';

    return t;
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (auth) {
      final raw = await AuthStorage.getToken();
      if (raw != null) {
        final token = _cleanToken(raw);
        if (token.isNotEmpty) {
          h['Authorization'] = 'Bearer $token';
        }
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

  // ===== Verbs =====
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
        .timeout(_timeout);

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
        .timeout(_timeout);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _decodeJson(res.body);
    }
    throw _httpError(res.statusCode, res.body);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final res = await http
        .patch(
          _uri(path, query),
          headers: await _headers(auth: auth),
          body: json.encode(body ?? {}),
        )
        .timeout(_timeout);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // บาง backend อาจคืน 204 body ว่าง
      if (res.body.trim().isEmpty) {
        return {'ok': true, 'statusCode': res.statusCode};
      }
      return _decodeJson(res.body);
    }
    throw _httpError(res.statusCode, res.body);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final res = await http
        .put(
          _uri(path, query),
          headers: await _headers(auth: auth),
          body: json.encode(body ?? {}),
        )
        .timeout(_timeout);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.trim().isEmpty) {
        return {'ok': true, 'statusCode': res.statusCode};
      }
      return _decodeJson(res.body);
    }
    throw _httpError(res.statusCode, res.body);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final req = http.Request('DELETE', _uri(path, query));
    req.headers.addAll(await _headers(auth: auth));
    if (body != null) {
      req.body = json.encode(body);
    }

    final streamed = await req.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.trim().isEmpty) {
        return {'ok': true, 'statusCode': res.statusCode};
      }
      return _decodeJson(res.body);
    }
    throw _httpError(res.statusCode, res.body);
  }
}
