import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AttendanceApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic> data;

  const AttendanceApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  bool get isPreviousAttendancePending =>
      code == 'PREVIOUS_ATTENDANCE_PENDING';

  bool get isShiftNotResolved => code == 'SHIFT_NOT_RESOLVED';

  bool get isManualRequestPending => code == 'MANUAL_REQUEST_PENDING';

  bool get isAlreadyCheckedIn => code == 'ALREADY_CHECKED_IN';

  bool get isAlreadyCheckedInOtherSession =>
      code == 'ALREADY_CHECKED_IN_OTHER_SESSION';

  bool get isNoOpenSession => code == 'NO_OPEN_SESSION';

  String get previousSessionId => '${data['previousSessionId'] ?? ''}'.trim();
  String get previousClinicId => '${data['previousClinicId'] ?? ''}'.trim();
  String get previousWorkDate => '${data['previousWorkDate'] ?? ''}'.trim();
  String get previousShiftId => '${data['previousShiftId'] ?? ''}'.trim();
  String get action => '${data['action'] ?? ''}'.trim();

  Map<String, dynamic> get previousSession {
    final raw = data['previousSession'];
    if (raw is Map<String, dynamic>) return raw;
    return <String, dynamic>{};
  }

  @override
  String toString() {
    if (code.isNotEmpty) {
      return 'AttendanceApiException($statusCode, $code, $message)';
    }
    return 'AttendanceApiException($statusCode, $message)';
  }
}

class AttendanceApi {
  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic> _decodeResponse(http.Response res) {
    try {
      final raw = res.body.trim();
      if (raw.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'data': decoded};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _extractErrorMessage(
    http.Response res,
    Map<String, dynamic> data,
    String fallback,
  ) {
    final code = '${data['code'] ?? ''}'.trim();
    final message = '${data['message'] ?? ''}'.trim();

    if (message.isNotEmpty) {
      if (code.isNotEmpty) return '$message [$code]';
      return message;
    }
    return '$fallback (${res.statusCode})';
  }

  static Never _throwApiError(
    http.Response res,
    Map<String, dynamic> data,
    String fallback,
  ) {
    final code = '${data['code'] ?? ''}'.trim();
    final message = _extractErrorMessage(res, data, fallback);

    throw AttendanceApiException(
      statusCode: res.statusCode,
      code: code,
      message: message,
      data: data,
    );
  }

  static Uri _buildUri(
    String path, [
    Map<String, String>? query,
  ]) {
    return Uri.parse('${ApiConfig.payrollBaseUrl}$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  static Future<Map<String, dynamic>> checkIn({
    required String token,
    required String workDate,
    String? shiftId,
    required bool biometricVerified,
    String deviceId = '',
    double? lat,
    double? lng,
    String note = '',
  }) async {
    final url = _buildUri('/attendance/check-in');

    final body = <String, dynamic>{
      'workDate': workDate,
      'method': 'biometric',
      'biometricVerified': biometricVerified,
      'deviceId': deviceId,
      'note': note,
      if ((shiftId ?? '').trim().isNotEmpty) 'shiftId': shiftId!.trim(),
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };

    final res = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode(body),
    );

    final data = _decodeResponse(res);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    _throwApiError(res, data, 'checkIn failed');
  }

  static Future<Map<String, dynamic>> checkOut({
    required String token,
    String? sessionId,
    String? workDate,
    String? shiftId,
    required bool biometricVerified,
    String deviceId = '',
    double? lat,
    double? lng,
    String note = '',
    String reasonCode = '',
    String reasonText = '',
  }) async {
    final hasSessionId = (sessionId ?? '').trim().isNotEmpty;

    final url = hasSessionId
        ? _buildUri('/attendance/${sessionId!.trim()}/check-out')
        : _buildUri('/attendance/check-out');

    final body = <String, dynamic>{
      'method': 'biometric',
      'biometricVerified': biometricVerified,
      'deviceId': deviceId,
      'note': note,
      if ((workDate ?? '').trim().isNotEmpty) 'workDate': workDate!.trim(),
      if ((shiftId ?? '').trim().isNotEmpty) 'shiftId': shiftId!.trim(),
      if (reasonCode.trim().isNotEmpty) 'reasonCode': reasonCode.trim(),
      if (reasonText.trim().isNotEmpty) 'reasonText': reasonText.trim(),
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };

    final res = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode(body),
    );

    final data = _decodeResponse(res);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    _throwApiError(res, data, 'checkOut failed');
  }

  static Future<Map<String, dynamic>> mySessions({
    required String token,
    String? dateFrom,
    String? dateTo,
    String? clinicId,
    String? shiftId,
  }) async {
    final q = <String, String>{};

    if ((dateFrom ?? '').trim().isNotEmpty) q['dateFrom'] = dateFrom!.trim();
    if ((dateTo ?? '').trim().isNotEmpty) q['dateTo'] = dateTo!.trim();
    if ((clinicId ?? '').trim().isNotEmpty) q['clinicId'] = clinicId!.trim();
    if ((shiftId ?? '').trim().isNotEmpty) q['shiftId'] = shiftId!.trim();

    final url = _buildUri('/attendance/me', q);

    final res = await http.get(url, headers: _headers(token));
    final data = _decodeResponse(res);

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    _throwApiError(res, data, 'list sessions failed');
  }

  static Future<Map<String, dynamic>> myDayPreview({
    required String token,
    required String workDate,
    String? shiftId,
  }) async {
    final q = <String, String>{
      'workDate': workDate,
      if ((shiftId ?? '').trim().isNotEmpty) 'shiftId': shiftId!.trim(),
    };

    final url = _buildUri('/attendance/me-preview', q);

    final res = await http.get(url, headers: _headers(token));
    final data = _decodeResponse(res);

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    _throwApiError(res, data, 'preview failed');
  }

  static Future<Map<String, dynamic>> submitManualRequest({
    required String token,
    required String workDate,
    required String manualRequestType,
    String? shiftId,
    String? requestedCheckInAt,
    String? requestedCheckOutAt,
    String note = '',
    String reasonCode = '',
    String reasonText = '',
  }) async {
    final url = _buildUri('/attendance/manual-request');

    final body = <String, dynamic>{
      'workDate': workDate,
      'manualRequestType': manualRequestType,
      'note': note,
      if ((shiftId ?? '').trim().isNotEmpty) 'shiftId': shiftId!.trim(),
      if ((requestedCheckInAt ?? '').trim().isNotEmpty)
        'requestedCheckInAt': requestedCheckInAt!.trim(),
      if ((requestedCheckOutAt ?? '').trim().isNotEmpty)
        'requestedCheckOutAt': requestedCheckOutAt!.trim(),
      if (reasonCode.trim().isNotEmpty) 'reasonCode': reasonCode.trim(),
      if (reasonText.trim().isNotEmpty) 'reasonText': reasonText.trim(),
    };

    final res = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode(body),
    );

    final data = _decodeResponse(res);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    _throwApiError(res, data, 'submit manual request failed');
  }

  static Future<Map<String, dynamic>> myManualRequests({
    required String token,
    String? workDate,
    String? approvalStatus,
    String? clinicId,
    String? shiftId,
  }) async {
    final q = <String, String>{};

    if ((workDate ?? '').trim().isNotEmpty) q['workDate'] = workDate!.trim();
    if ((approvalStatus ?? '').trim().isNotEmpty) {
      q['approvalStatus'] = approvalStatus!.trim();
    }
    if ((clinicId ?? '').trim().isNotEmpty) q['clinicId'] = clinicId!.trim();
    if ((shiftId ?? '').trim().isNotEmpty) q['shiftId'] = shiftId!.trim();

    final url = _buildUri('/attendance/manual-request/my', q);

    final res = await http.get(url, headers: _headers(token));
    final data = _decodeResponse(res);

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    _throwApiError(res, data, 'list manual requests failed');
  }
}