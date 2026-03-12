import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AttendanceAnalyticsService {
  final String baseUrl;
  final String token;

  const AttendanceAnalyticsService({
    required this.baseUrl,
    required this.token,
  });

  Future<Map<String, dynamic>> fetchClinicAnalytics(String month) async {
    final cleanBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final cleanToken = token.trim();
    final cleanMonth = month.trim();

    if (cleanBaseUrl.isEmpty) {
      throw Exception('Base URL ว่าง');
    }

    if (cleanToken.isEmpty) {
      throw Exception('Token ว่าง');
    }

    if (cleanMonth.isEmpty) {
      throw Exception('Month ว่าง');
    }

    final paths = <String>[
      '/attendance/analytics/clinic?month=$cleanMonth',
      '/api/attendance/analytics/clinic?month=$cleanMonth',
    ];

    Object? lastError;

    for (final path in paths) {
      try {
        final uri = Uri.parse('$cleanBaseUrl$path');

        final response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $cleanToken',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);

          if (decoded is Map<String, dynamic>) {
            return decoded;
          }

          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }

          throw Exception('รูปแบบข้อมูล analytics ไม่ถูกต้อง');
        }

        if (response.statusCode == 404) {
          lastError = Exception('endpoint not found: $path');
          continue;
        }

        String message = 'Failed to load analytics';

        try {
          final body = jsonDecode(response.body);
          if (body is Map) {
            final apiMessage = body['message']?.toString().trim() ?? '';
            if (apiMessage.isNotEmpty) {
              message = apiMessage;
            }
          }
        } catch (_) {}

        throw Exception('$message (status: ${response.statusCode})');
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError?.toString() ?? 'ไม่สามารถโหลด analytics ได้');
  }
}