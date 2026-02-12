import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:clinic_payroll/api/api_config.dart';

class TrustScoreApi {
  /// GET trust score ของ staff
  static Future<Map<String, dynamic>> getStaffScore({
    required String staffId,
    String? token, // ถ้า backend เปิด auth
  }) async {
    final url = Uri.parse(
      ApiConfig.scoreBaseUrl + ApiConfig.staffScore(staffId),
    );

    final res = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode != 200) {
      throw Exception(
        'getStaffScore failed: ${res.statusCode} ${res.body}',
      );
    }

    return json.decode(res.body) as Map<String, dynamic>;
  }

  /// POST attendance event (update score)
  static Future<Map<String, dynamic>> postAttendanceEvent({
    required String clinicId,
    required String staffId,
    required String status, // completed | late | no_show | cancelled_early
    String shiftId = '',
    int minutesLate = 0,
    String? token,
  }) async {
    final url = Uri.parse(
      ApiConfig.scoreBaseUrl + ApiConfig.attendanceEvent,
    );

    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'clinicId': clinicId,
        'staffId': staffId,
        'shiftId': shiftId,
        'status': status,
        'minutesLate': minutesLate,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(
        'postAttendanceEvent failed: ${res.statusCode} ${res.body}',
      );
    }

    return json.decode(res.body) as Map<String, dynamic>;
  }
}
