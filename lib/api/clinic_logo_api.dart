import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class ClinicLogoApi {
  static String get _baseUrl => ApiConfig.payrollBaseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getToken();

    return {
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Bearer ${token.trim()}',
    };
  }

  static Uri _buildUri(String path) {
    final base = _baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final p = path.trim().startsWith('/') ? path.trim() : '/$path';
    return Uri.parse('$base$p');
  }

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return 'logo.png';

    final parts = normalized.split('/');
    final last = parts.isNotEmpty ? parts.last.trim() : '';
    if (last.isEmpty) return 'logo.png';

    return last;
  }

  static String _normalizeUploadFileName(String path) {
    final raw = _fileNameFromPath(path);
    final lower = raw.toLowerCase();

    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return raw;
    }

    return '$raw.png';
  }

  static Future<Map<String, dynamic>> uploadLogo({
    required String clinicId,
    required File file,
  }) async {
    final cid = clinicId.trim();
    if (cid.isEmpty) {
      throw Exception('clinicId is required');
    }

    if (!await file.exists()) {
      throw Exception('ไม่พบไฟล์รูปที่เลือก');
    }

    final uri = _buildUri('/api/upload/logo/$cid');
    final headers = await _headers();
    final fileName = _normalizeUploadFileName(file.path);

    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);
    request.files.add(
      await http.MultipartFile.fromPath(
        'logo',
        file.path,
        filename: fileName,
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    Map<String, dynamic> body = <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(
      (body['message'] ?? 'อัปโหลดโลโก้ไม่สำเร็จ').toString(),
    );
  }

  static Future<Map<String, dynamic>> removeLogo({
    required String clinicId,
  }) async {
    final cid = clinicId.trim();
    if (cid.isEmpty) {
      throw Exception('clinicId is required');
    }

    final uri = _buildUri('/api/upload/logo/$cid');
    final headers = await _headers();

    final response = await http.delete(uri, headers: headers);

    Map<String, dynamic> body = <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(
      (body['message'] ?? 'ลบโลโก้ไม่สำเร็จ').toString(),
    );
  }
}