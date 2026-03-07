// lib/api/api_client.dart
//
// ✅ FINAL — SINGLE SOURCE OF TRUTH FOR AUTH HEADER (JWT + OPAQUE TOKEN SAFE)
// + ✅ DEBUG LOGGER (debug mode only): method/url/auth/status/body-preview
// + ✅ FRIENDLY NETWORK ERROR: timeout / socket / connection
// + ✅ BETTER HTTP ERROR MAPPING: 401/403/400/500
//
// - sanitize token (trim / remove quotes / remove leading "Bearer " / reject null)
// - ✅ ALLOW non-JWT token (opaque tokens)  ❗️ไม่บังคับต้องมี 3 ส่วน a.b.c
// - ✅ if auth=true but token missing/invalid -> throw (ไม่เงียบ)
// - Render-safe timeout (60s) กัน cold start
// - supports: GET / POST / PATCH / PUT / DELETE
//
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  // ===== Debug log (only in debug mode) =====
  void _d(String msg) {
    // assert runs only in debug mode
    assert(() {
      // ignore: avoid_print
      print(msg);
      return true;
    }());
  }

  String _preview(String s, {int max = 260}) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}...';
  }

  // ===== Token sanitize =====
  String _cleanToken(String raw) {
    var t = raw.trim();

    // กันเคสเก็บมาเป็น "...." (มี quote ครอบ)
    if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
      t = t.substring(1, t.length - 1).trim();
    }

    // กันเคสเก็บมาเป็น Bearer xxx (ซ้ำหลายรอบก็เอาออกให้หมด)
    while (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }

    // กัน newline/space แปลก ๆ (token ไม่ควรมี whitespace)
    t = t.replaceAll(RegExp(r'\s+'), '').trim();

    // กัน "null" / ว่าง
    if (t.isEmpty || t.toLowerCase() == 'null') return '';

    // ✅ IMPORTANT:
    // ❌ ไม่บังคับต้องเป็น JWT แล้ว (รองรับ opaque token)
    return t;
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (!auth) return h;

    final raw = await AuthStorage.getToken();
    if (raw == null) {
      // ✅ ให้พังแบบมีเหตุผล
      throw Exception('AUTH_REQUIRED');
    }

    final token = _cleanToken(raw);
    if (token.isEmpty) {
      throw Exception('AUTH_REQUIRED');
    }

    h['Authorization'] = 'Bearer $token';
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

    // ✅ map เป็นข้อความที่ UI แยกได้ง่ายขึ้น (ยังคงเป็น Exception ตัวเดียว)
    if (code == 401) return Exception('API 401: SESSION_EXPIRED');
    if (code == 403) return Exception('API 403: FORBIDDEN');
    if (code >= 500) return Exception('API $code: SERVER_ERROR');

    return Exception('API $code: $msg');
  }

  Exception _netError(Object e) {
    if (e is TimeoutException) {
      return Exception('NETWORK_TIMEOUT');
    }
    if (e is SocketException) {
      return Exception('NETWORK_ERROR');
    }
    // บางที http โยน ClientException
    final s = e.toString().toLowerCase();
    if (s.contains('socket') ||
        s.contains('failed host lookup') ||
        s.contains('connection') ||
        s.contains('network')) {
      return Exception('NETWORK_ERROR');
    }
    return Exception(e.toString());
  }

  // ===== Verbs =====
  Future<Map<String, dynamic>> get(
    String path, {
    bool auth = true,
    Map<String, String>? query,
  }) async {
    final url = _uri(path, query);
    _d('[API] GET $url auth=$auth');

    try {
      final res = await http
          .get(url, headers: await _headers(auth: auth))
          .timeout(_timeout);

      _d('[API] <- ${res.statusCode} GET $url body="${_preview(res.body)}"');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return _decodeJson(res.body);
      }
      throw _httpError(res.statusCode, res.body);
    } catch (e) {
      _d('[API] !! GET $url error="${e.toString()}"');
      throw _netError(e);
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final url = _uri(path, query);
    final payload = json.encode(body ?? {});
    _d('[API] POST $url auth=$auth body="${_preview(payload)}"');

    try {
      final res = await http
          .post(url, headers: await _headers(auth: auth), body: payload)
          .timeout(_timeout);

      _d('[API] <- ${res.statusCode} POST $url body="${_preview(res.body)}"');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return _decodeJson(res.body);
      }
      throw _httpError(res.statusCode, res.body);
    } catch (e) {
      _d('[API] !! POST $url error="${e.toString()}"');
      throw _netError(e);
    }
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final url = _uri(path, query);
    final payload = json.encode(body ?? {});
    _d('[API] PATCH $url auth=$auth body="${_preview(payload)}"');

    try {
      final res = await http
          .patch(url, headers: await _headers(auth: auth), body: payload)
          .timeout(_timeout);

      _d('[API] <- ${res.statusCode} PATCH $url body="${_preview(res.body)}"');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.trim().isEmpty) {
          return {'ok': true, 'statusCode': res.statusCode};
        }
        return _decodeJson(res.body);
      }
      throw _httpError(res.statusCode, res.body);
    } catch (e) {
      _d('[API] !! PATCH $url error="${e.toString()}"');
      throw _netError(e);
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final url = _uri(path, query);
    final payload = json.encode(body ?? {});
    _d('[API] PUT $url auth=$auth body="${_preview(payload)}"');

    try {
      final res = await http
          .put(url, headers: await _headers(auth: auth), body: payload)
          .timeout(_timeout);

      _d('[API] <- ${res.statusCode} PUT $url body="${_preview(res.body)}"');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.trim().isEmpty) {
          return {'ok': true, 'statusCode': res.statusCode};
        }
        return _decodeJson(res.body);
      }
      throw _httpError(res.statusCode, res.body);
    } catch (e) {
      _d('[API] !! PUT $url error="${e.toString()}"');
      throw _netError(e);
    }
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    bool auth = true,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final url = _uri(path, query);
    _d('[API] DELETE $url auth=$auth body="${_preview(json.encode(body ?? {}))}"');

    try {
      final req = http.Request('DELETE', url);
      req.headers.addAll(await _headers(auth: auth));
      if (body != null) {
        req.body = json.encode(body);
      }

      final streamed = await req.send().timeout(_timeout);
      final res = await http.Response.fromStream(streamed);

      _d('[API] <- ${res.statusCode} DELETE $url body="${_preview(res.body)}"');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.trim().isEmpty) {
          return {'ok': true, 'statusCode': res.statusCode};
        }
        return _decodeJson(res.body);
      }
      throw _httpError(res.statusCode, res.body);
    } catch (e) {
      _d('[API] !! DELETE $url error="${e.toString()}"');
      throw _netError(e);
    }
  }
}