// lib/services/score_service.dart
//
// ✅ FINAL — USE ApiClient ONLY (single source of truth for Authorization)
// - ตัดการอ่าน token จาก SharedPreferences หลาย key (กัน jwt malformed)
// - ใช้ ApiClient ที่ sanitize token + Render-safe timeout
// - ใช้ ApiConfig.scoreBaseUrl + endpoint จาก ApiConfig (mount /score)
//
import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/staff_score_model.dart';

class ScoreService {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.scoreBaseUrl);

  // ======================================================
  // GET /score/staff/:staffId/score   (ตาม ApiConfig.staffScore)
  // ======================================================
  static Future<StaffScore> getStaffScore(String staffId) async {
    final sid = staffId.trim();
    if (sid.isEmpty) {
      throw Exception('staffId is required');
    }

    final decoded = await _client.get(
      ApiConfig.staffScore(sid),
      auth: true,
    );

    // บาง backend อาจคืน {ok:true, data:{...}} หรือ {score:{...}}
    final dynamic payload = decoded['data'] ?? decoded['score'] ?? decoded;

    if (payload is Map<String, dynamic>) {
      return StaffScore.fromMap(payload);
    }
    if (payload is Map) {
      return StaffScore.fromMap(Map<String, dynamic>.from(payload));
    }

    // fallback: ถ้า backend คืน map ทั้งก้อนเลย
    if (decoded is Map<String, dynamic>) {
      return StaffScore.fromMap(decoded);
    }

    throw Exception('Invalid staff score response: ${payload.runtimeType}');
  }

  // ======================================================
  // POST /score/events/attendance   (ตาม ApiConfig.attendanceEvent)
  // ======================================================
  static Future<Map<String, dynamic>> postAttendanceEvent({
    required String clinicId,
    required String staffId,
    String shiftId = '',
    required String status, // completed|late|cancelled_early|no_show
    int minutesLate = 0,
    bool auth = true,
  }) async {
    return _client.post(
      ApiConfig.attendanceEvent,
      auth: auth,
      body: <String, dynamic>{
        'clinicId': clinicId,
        'staffId': staffId,
        'shiftId': shiftId,
        'status': status,
        'minutesLate': minutesLate,
      },
    );
  }
}
