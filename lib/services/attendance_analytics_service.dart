import 'dart:convert';
import 'package:http/http.dart' as http;

class AttendanceAnalyticsService {
  final String baseUrl;
  final String token;

  AttendanceAnalyticsService({
    required this.baseUrl,
    required this.token,
  });

  Future<Map<String, dynamic>> fetchClinicAnalytics(String date) async {
    final url = Uri.parse("$baseUrl/attendance/analytics/clinic?date=$date");

    final res = await http.get(
      url,
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (res.statusCode != 200) {
      throw Exception("Failed to load analytics");
    }

    return jsonDecode(res.body);
  }
}