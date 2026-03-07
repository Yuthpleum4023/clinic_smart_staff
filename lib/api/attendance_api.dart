import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AttendanceApi {
  static Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  static Future<Map<String, dynamic>> checkIn({
    required String token,
    required String workDate, // yyyy-MM-dd
    String? shiftId,
    required bool biometricVerified,
    String deviceId = '',
    double? lat,
    double? lng,
    String note = '',
  }) async {
    final url = Uri.parse('${ApiConfig.payrollBaseUrl}/attendance/check-in');
    final res = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'workDate': workDate,
        if (shiftId != null) 'shiftId': shiftId,
        'method': 'biometric',
        'biometricVerified': biometricVerified,
        'deviceId': deviceId,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'note': note,
      }),
    );

    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw Exception(data['message'] ?? 'checkIn failed (${res.statusCode})');
  }

  static Future<Map<String, dynamic>> checkOut({
    required String token,
    required String sessionId,
    required bool biometricVerified,
    String deviceId = '',
    double? lat,
    double? lng,
    String note = '',
  }) async {
    final url = Uri.parse('${ApiConfig.payrollBaseUrl}/attendance/$sessionId/check-out');
    final res = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'method': 'biometric',
        'biometricVerified': biometricVerified,
        'deviceId': deviceId,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'note': note,
      }),
    );

    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    throw Exception(data['message'] ?? 'checkOut failed (${res.statusCode})');
  }

  static Future<Map<String, dynamic>> mySessions({
    required String token,
    String? dateFrom,
    String? dateTo,
  }) async {
    final q = <String, String>{};
    if (dateFrom != null) q['dateFrom'] = dateFrom;
    if (dateTo != null) q['dateTo'] = dateTo;

    final url = Uri.parse('${ApiConfig.payrollBaseUrl}/attendance/me').replace(queryParameters: q);
    final res = await http.get(url, headers: _headers(token));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode == 200) return data;
    throw Exception(data['message'] ?? 'list sessions failed (${res.statusCode})');
  }
}