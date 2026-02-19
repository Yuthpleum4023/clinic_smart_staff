// lib/api/trust_score_api.dart
//
// ✅ FINAL — USE ApiClient (single source of truth for Authorization)
// - ไม่รับ token จากภายนอกแล้ว (กัน token เพี้ยน)
// - ใช้ ApiClient ที่ sanitize token + Render-safe timeout
// - รองรับ score_service mount ที่ /score ตาม ApiConfig.staffScore()
//
import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';

class TrustScoreApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.scoreBaseUrl);

  /// GET trust score ของ staff
  static Future<Map<String, dynamic>> getStaffScore({
    required String staffId,
    bool auth = true,
  }) async {
    // ApiConfig.staffScore(staffId) => '/score/staff/:id/score'
    return _client.get(
      ApiConfig.staffScore(staffId),
      auth: auth,
    );
  }

  /// POST attendance event (update score)
  static Future<Map<String, dynamic>> postAttendanceEvent({
    required String clinicId,
    required String staffId,
    required String status, // completed | late | no_show | cancelled_early
    String shiftId = '',
    int minutesLate = 0,
    bool auth = true,
  }) async {
    return _client.post(
      ApiConfig.attendanceEvent, // '/score/events/attendance'
      auth: auth,
      body: {
        'clinicId': clinicId,
        'staffId': staffId,
        'shiftId': shiftId,
        'status': status,
        'minutesLate': minutesLate,
      },
    );
  }
}
