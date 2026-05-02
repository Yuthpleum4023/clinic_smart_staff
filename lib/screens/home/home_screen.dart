import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

// ✅ Biometric
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/attendance_api.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/services/auth_service.dart';

import 'package:clinic_smart_staff/app/app_context.dart';
import 'package:clinic_smart_staff/app/app_context_resolver.dart';

import 'package:clinic_smart_staff/screens/clinic/clinic_home_screen.dart';
import 'package:clinic_smart_staff/screens/helper/helper_home_screen.dart';
import 'package:clinic_smart_staff/screens/helper/helper_marketplace_screen.dart';

import 'package:clinic_smart_staff/screens/clinic_shift_need_list_screen.dart';
import 'package:clinic_smart_staff/screens/helper_open_needs_screen.dart';
import 'package:clinic_smart_staff/screens/trustscore_lookup_screen.dart';

import 'package:clinic_smart_staff/models/employee_model.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';
import 'package:clinic_smart_staff/screens/employee_detail_screen.dart';
import 'package:clinic_smart_staff/screens/add_employee_screen.dart';
import 'package:clinic_smart_staff/screens/payslip_preview_screen.dart';

import 'package:clinic_smart_staff/main.dart';

import 'package:clinic_smart_staff/screens/home/tabs/home_tab.dart';
import 'package:clinic_smart_staff/screens/home/tabs/my_tab.dart';
import 'package:clinic_smart_staff/screens/home/widgets/attendance_card.dart';
import 'package:clinic_smart_staff/screens/home/widgets/premium_gate_card.dart';
import 'package:clinic_smart_staff/screens/home/widgets/policy_card.dart';
import 'package:clinic_smart_staff/screens/home/widgets/urgent_jobs_card.dart';
import 'package:clinic_smart_staff/screens/home/attendance/attendance_history_screen.dart';
import 'package:clinic_smart_staff/screens/home/attendance/manual_attendance_request_screen.dart';

enum _AttendanceSubmitResult {
  success,
  alreadyDone,
  unauthorized,
  forbidden,
  failed,
  manualRequired,
  earlyCheckoutReasonRequired,
  shiftSelectionRequired,
  checkedInOtherClinic,
  multipleOpenSessions,
  locationPermissionDenied,
  locationServiceDisabled,
  locationUnavailable,
  previousAttendancePending,
}

enum _AttendanceUiPhase {
  idle,
  checkingInBio,
  checkingInSubmit,
  checkingOutBio,
  checkingOutSubmit,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _didSetInitialTab = false;

  bool _ctxLoading = true;
  String _ctxErr = '';
  String _role = '';
  String _clinicId = '';
  String _userId = '';
  String _staffId = '';

  static const String _kPremiumAttendanceKey = 'premium_attendance_enabled';
  bool _premiumLoading = true;
  bool _premiumAttendanceEnabled = false;

  bool _policyLoading = false;
  String _policyErr = '';
  Map<String, dynamic> _policy = <String, dynamic>{};
  Map<String, dynamic> _features = <String, dynamic>{};
  List<String> _policyLines = [];

  bool _urgentLoading = false;
  bool _activeRefreshing = false;
  String _urgentErr = '';
  int _urgentCount = 0;
  Map<String, dynamic>? _urgentFirst;

  bool _payslipLoading = false;
  String _payslipErr = '';
  List<Map<String, dynamic>> _closedMonths = [];

  bool _attLoading = false;
  String _attErr = '';
  String _attStatusLine = '';
  bool _attCheckedIn = false;
  bool _attCheckedOut = false;
  bool _attPosting = false;

  int _attRefreshSeq = 0;
  bool _attActionLock = false;
  bool _openingPayslipPicker = false;
  bool _checkingAttendanceLocation = false;
  bool _openingManualRequestFlow = false;

  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _bioLoading = false;

  _AttendanceUiPhase _attUiPhase = _AttendanceUiPhase.idle;
  String _attProgressText = '';
  bool _showSlowNetworkHint = false;
  Timer? _slowNetworkTimer;

  bool get _attBusy => _attUiPhase != _AttendanceUiPhase.idle;

  bool _attLocationLoading = false;
  String _attLocationError = '';
  double? _attLat;
  double? _attLng;
  double? _attAccuracyMeters;

  bool _attBlockedByPreviousPending = false;
  String _attPreviousPendingMessage = '';
  String _attPreviousSessionId = '';
  String _attPreviousWorkDate = '';
  String _attPreviousShiftId = '';
  String _attPreviousClinicId = '';
  String _attPreviousClinicName = '';
  String _attPreviousAction = '';
  Map<String, dynamic> _attPreviousSession = <String, dynamic>{};

  bool get _hasPreviousPendingBlock => _attBlockedByPreviousPending;

  String get _displayAttendanceStatusLine {
    final previousPendingLine = _hasPreviousPendingBlock
        ? (_attPreviousPendingMessage.trim().isNotEmpty
            ? _attPreviousPendingMessage.trim()
            : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน')
        : '';

    final base = previousPendingLine.isNotEmpty
        ? previousPendingLine
        : (_attProgressText.trim().isNotEmpty
            ? _attProgressText.trim()
            : _attStatusLine.trim());

    if (_showSlowNetworkHint) {
      if (base.isEmpty) {
        return 'อินเทอร์เน็ตค่อนข้างช้า กรุณารอสักครู่';
      }
      return '$base\nอินเทอร์เน็ตค่อนข้างช้า กรุณารอสักครู่';
    }

    return base;
  }

  bool _helperShiftLoading = false;
  String _helperShiftErr = '';
  List<Map<String, dynamic>> _helperTodayShifts = <Map<String, dynamic>>[];
  Map<String, dynamic>? _selectedHelperShift;
  bool _helperShiftTouchedByUser = false;
  String _helperRuntimeShiftSelectionMode = '';

  bool get _helperHasMultipleShifts => _helperTodayShifts.length > 1;

  bool get _helperNeedsShiftSelection =>
      _isHelper && _attendancePremiumEnabled && _helperTodayShifts.isNotEmpty;

  String get _selectedHelperShiftId {
    final raw = (_selectedHelperShift?['_id'] ??
            _selectedHelperShift?['id'] ??
            _selectedHelperShift?['shiftId'] ??
            '')
        .toString()
        .trim();
    return raw;
  }

  String get _selectedHelperShiftClinicId {
    final raw = (_selectedHelperShift?['clinicId'] ??
            _selectedHelperShift?['clinic']?['_id'] ??
            _selectedHelperShift?['clinic']?['id'] ??
            '')
        .toString()
        .trim();
    return raw;
  }

  String get _selectedHelperShiftLabel {
    final sh = _selectedHelperShift;
    if (sh == null) return 'ยังไม่ได้เลือกกะ';

    final clinicName = _helperShiftClinicName(sh);
    final date = _helperShiftDate(sh);
    final start = _helperShiftStart(sh);
    final end = _helperShiftEnd(sh);
    final title = _helperShiftTitle(sh);

    final parts = <String>[];
    if (clinicName.isNotEmpty) parts.add(clinicName);
    if (title.isNotEmpty && title != clinicName) parts.add(title);
    if (date.isNotEmpty) parts.add(date);
    if (start.isNotEmpty || end.isNotEmpty) {
      parts.add(
        '${start.isEmpty ? '--:--' : start} - ${end.isEmpty ? '--:--' : end}',
      );
    }

    if (parts.isEmpty) return 'เลือกกะแล้ว';
    return parts.join(' • ');
  }

  @override
  void initState() {
    super.initState();
    _bootstrapContext();
  }

  @override
  void dispose() {
    _slowNetworkTimer?.cancel();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _tapLog(String msg) {
    print('TAP -> $msg');
  }

  String _norm(String s) => s.trim().toLowerCase();

  bool _isTruthy(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  void _clearPreviousPendingBlock() {
    if (!mounted) return;
    setState(() {
      _attBlockedByPreviousPending = false;
      _attPreviousPendingMessage = '';
      _attPreviousSessionId = '';
      _attPreviousWorkDate = '';
      _attPreviousShiftId = '';
      _attPreviousClinicId = '';
      _attPreviousClinicName = '';
      _attPreviousAction = '';
      _attPreviousSession = <String, dynamic>{};
    });
  }

  void _applyPreviousPendingBlockFromMap(Map<String, dynamic> data) {
    final previousAny = data['previousSession'];
    final previous = previousAny is Map
        ? Map<String, dynamic>.from(previousAny)
        : <String, dynamic>{};

    final pendingContextAny = data['pendingContext'];
    final pendingContext = pendingContextAny is Map
        ? Map<String, dynamic>.from(pendingContextAny)
        : <String, dynamic>{};

    final previousSessionId = (data['previousSessionId'] ??
            previous['_id'] ??
            previous['sessionId'] ??
            pendingContext['_id'] ??
            pendingContext['sessionId'] ??
            '')
        .toString()
        .trim();

    final previousWorkDate = (data['previousWorkDate'] ??
            previous['workDate'] ??
            pendingContext['workDate'] ??
            '')
        .toString()
        .trim();

    final previousShiftId = (data['previousShiftId'] ??
            previous['shiftId'] ??
            pendingContext['shiftId'] ??
            '')
        .toString()
        .trim();

    final previousClinicId = (data['previousClinicId'] ??
            previous['clinicId'] ??
            pendingContext['clinicId'] ??
            '')
        .toString()
        .trim();

    final previousClinicName = (data['previousClinicName'] ??
            previous['clinicName'] ??
            previous['clinicLabel'] ??
            pendingContext['clinicName'] ??
            pendingContext['clinicLabel'] ??
            '')
        .toString()
        .trim();

    final previousMessage = (data['message'] ?? '').toString().trim();
    final action = (data['action'] ?? '').toString().trim();

    if (!mounted) return;
    setState(() {
      _attBlockedByPreviousPending = true;
      _attPreviousPendingMessage = previousMessage;
      _attPreviousSessionId = previousSessionId;
      _attPreviousWorkDate = previousWorkDate;
      _attPreviousShiftId = previousShiftId;
      _attPreviousClinicId = previousClinicId;
      _attPreviousClinicName = previousClinicName;
      _attPreviousAction = action;
      _attPreviousSession = previous.isNotEmpty ? previous : pendingContext;
      _attCheckedIn = false;
      _attCheckedOut = false;
      _attErr = '';
      _attStatusLine = previousMessage.isNotEmpty
          ? previousMessage
          : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน';
    });
  }

  String _friendlyAuthError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('no token') || s.contains('token')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง';
    }
    if (s.contains('timeout')) {
      return 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่';
    }
    if (s.contains('unauthorized') || s.contains('401')) {
      return 'ไม่สามารถยืนยันตัวตนได้ กรุณาเข้าสู่ระบบอีกครั้ง';
    }
    if (s.contains('forbidden') || s.contains('403')) {
      return 'คุณไม่มีสิทธิ์ใช้งานเมนูนี้';
    }
    if (s.contains('missing staffid') || s.contains('staffid')) {
      return 'ไม่พบข้อมูลพนักงานของบัญชีนี้ กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่';
    }
    if (s.contains('missing clinic')) {
      return 'ไม่พบข้อมูลคลินิกของบัญชีนี้ กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่';
    }
    return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
  }

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _humanYmd(String ymd) {
    final t = ymd.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) return t;
    final parts = t.split('-');
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString().trim());
  }

  bool get _policyRequireLocation {
    final p = _policy['requireLocation'];
    if (p is bool) return p;

    final f = _features['requireLocation'];
    if (f is bool) return f;

    return false;
  }

  int get _policyGeoRadiusMeters {
    final raw =
        _policy['geoRadiusMeters'] ?? _features['geoRadiusMeters'] ?? 200;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw.toString()) ?? 200;
  }

  bool get _attendanceNeedsLiveLocation {
    if (_isEmployee) return true;
    if (_policyRequireLocation) return true;
    return false;
  }

  String _locationRuleText() {
    final radius = _policyGeoRadiusMeters;
    if (_isEmployee) {
      return 'ต้องเปิด GPS และอยู่ในรัศมี $radius เมตรจากจุดที่คลินิกกำหนด';
    }
    return 'กรุณาเปิด GPS เพื่อให้ระบบตรวจสอบตำแหน่งปัจจุบัน';
  }

  String _formatAttendanceLocationSummary() {
    final hasCoords = _attLat != null && _attLng != null;
    final acc = _attAccuracyMeters;
    final accText =
        acc == null ? '' : ' • ความแม่นยำประมาณ ${acc.toStringAsFixed(0)} ม.';

    if (_attLocationLoading || _checkingAttendanceLocation) {
      return 'กำลังตรวจสอบตำแหน่งปัจจุบัน...';
    }

    if (_attLocationError.trim().isNotEmpty) {
      return _attLocationError.trim();
    }

    if (hasCoords) {
      return 'พร้อมใช้งาน • พบตำแหน่งแล้ว$accText';
    }

    return _locationRuleText();
  }

  void _setAttendanceLocationState({
    bool? loading,
    String? error,
    double? lat,
    double? lng,
    double? accuracyMeters,
    bool clearCoords = false,
  }) {
    if (!mounted) return;
    setState(() {
      if (loading != null) _attLocationLoading = loading;
      if (error != null) _attLocationError = error;
      if (clearCoords) {
        _attLat = null;
        _attLng = null;
        _attAccuracyMeters = null;
      }
      if (lat != null) _attLat = lat;
      if (lng != null) _attLng = lng;
      if (accuracyMeters != null) _attAccuracyMeters = accuracyMeters;
    });
  }

  Future<Position?> _readAttendancePosition({
    bool showErrorSnack = true,
  }) async {
    if (!_attendanceNeedsLiveLocation) {
      return null;
    }

    try {
      _setAttendanceLocationState(
        loading: true,
        error: '',
      );

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        const msg = 'กรุณาเปิด GPS ก่อนบันทึกเวลาทำงาน';
        _setAttendanceLocationState(
          loading: false,
          error: msg,
          clearCoords: true,
        );
        if (showErrorSnack) _snack(msg);
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        const msg = 'กรุณาอนุญาตการเข้าถึงตำแหน่งเพื่อบันทึกเวลาทำงาน';
        _setAttendanceLocationState(
          loading: false,
          error: msg,
          clearCoords: true,
        );
        if (showErrorSnack) _snack(msg);
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        const msg =
            'ระบบถูกปฏิเสธสิทธิ์ตำแหน่งถาวร กรุณาเปิดสิทธิ์ Location ในการตั้งค่าเครื่อง';
        _setAttendanceLocationState(
          loading: false,
          error: msg,
          clearCoords: true,
        );
        if (showErrorSnack) _snack(msg);
        return null;
      }

      Position? pos;

      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        final msg = _isEmployee
            ? 'ไม่สามารถอ่านตำแหน่งปัจจุบันได้ กรุณาลองใหม่อีกครั้ง'
            : 'ไม่สามารถตรวจสอบตำแหน่งปัจจุบันได้ กรุณาลองใหม่อีกครั้ง';
        _setAttendanceLocationState(
          loading: false,
          error: msg,
          clearCoords: true,
        );
        if (showErrorSnack) _snack(msg);
        return null;
      }

      _setAttendanceLocationState(
        loading: false,
        error: '',
        lat: pos.latitude,
        lng: pos.longitude,
        accuracyMeters: pos.accuracy,
      );

      print(
        '[ATTENDANCE][LOCATION] lat=${pos.latitude} lng=${pos.longitude} accuracy=${pos.accuracy}',
      );

      return pos;
    } catch (e) {
      final msg = 'ไม่สามารถตรวจสอบตำแหน่งได้ กรุณาลองใหม่อีกครั้ง';
      print('[ATTENDANCE][LOCATION] ERROR $e');
      _setAttendanceLocationState(
        loading: false,
        error: msg,
        clearCoords: true,
      );
      if (showErrorSnack) _snack(msg);
      return null;
    }
  }

  Map<String, dynamic> _appendAttendanceLocation(
    Map<String, dynamic> payload, {
    Position? position,
  }) {
    final out = Map<String, dynamic>.from(payload);

    final lat = position?.latitude ?? _attLat;
    final lng = position?.longitude ?? _attLng;
    final accuracy = position?.accuracy ?? _attAccuracyMeters;

    if (lat != null && lng != null) {
      out['lat'] = lat;
      out['lng'] = lng;
      out['latitude'] = lat;
      out['longitude'] = lng;
    }

    if (accuracy != null) {
      out['accuracyMeters'] = accuracy;
    }

    return out;
  }

  String _locationMessageFromApi({
    required String fallback,
    required http.Response? response,
  }) {
    if (response == null) return fallback;

    final apiMsg = _extractApiMessage(response);
    if (apiMsg.isNotEmpty) return apiMsg;

    final code = _extractApiCode(response).toUpperCase();
    if (code == 'LOCATION_REQUIRED') {
      return 'กรุณาเปิด GPS และอนุญาตตำแหน่งก่อนบันทึกเวลาทำงาน';
    }
    if (code == 'OUTSIDE_ALLOWED_RADIUS') {
      return 'คุณอยู่นอกพื้นที่คลินิกที่กำหนด ไม่สามารถบันทึกเวลาได้';
    }
    if (code == 'CLINIC_LOCATION_NOT_SET') {
      return 'ยังไม่ได้ตั้งพิกัดอ้างอิงของคลินิก กรุณาตั้งค่าก่อนใช้งาน';
    }

    return fallback;
  }

  String _helperShiftTitle(Map<String, dynamic> sh) {
    return (sh['title'] ??
            sh['shiftTitle'] ??
            sh['position'] ??
            sh['roleName'] ??
            sh['jobTitle'] ??
            '')
        .toString()
        .trim();
  }

  String _helperShiftClinicName(Map<String, dynamic> sh) {
    final clinicAny = sh['clinic'];
    if (clinicAny is Map) {
      final name = (clinicAny['name'] ??
              clinicAny['clinicName'] ??
              clinicAny['title'] ??
              '')
          .toString()
          .trim();
      if (name.isNotEmpty) return name;
    }

    return (sh['clinicName'] ??
            sh['clinicTitle'] ??
            sh['hospitalName'] ??
            sh['workplaceName'] ??
            sh['locationName'] ??
            sh['clinicId'] ??
            '')
        .toString()
        .trim();
  }

  String _helperShiftDate(Map<String, dynamic> sh) {
    final raw =
        (sh['date'] ?? sh['workDate'] ?? sh['day'] ?? '').toString().trim();
    return _humanYmd(raw);
  }

  String _helperShiftStart(Map<String, dynamic> sh) {
    return (sh['start'] ??
            sh['startTime'] ??
            sh['from'] ??
            sh['begin'] ??
            '')
        .toString()
        .trim();
  }

  String _helperShiftEnd(Map<String, dynamic> sh) {
    return (sh['end'] ?? sh['endTime'] ?? sh['to'] ?? sh['finish'] ?? '')
        .toString()
        .trim();
  }

  String _helperShiftIdentityKey(Map<String, dynamic> sh) {
    final id = (sh['_id'] ?? sh['id'] ?? sh['shiftId'] ?? '').toString().trim();
    if (id.isNotEmpty) return 'id:$id';

    final clinicId =
        (sh['clinicId'] ?? sh['clinic']?['_id'] ?? sh['clinic']?['id'] ?? '')
            .toString()
            .trim();
    final date = (sh['date'] ?? sh['workDate'] ?? '').toString().trim();
    final start = _helperShiftStart(sh);
    final end = _helperShiftEnd(sh);

    return 'fallback:$clinicId|$date|$start|$end';
  }

  bool _sameShiftIdentity(
    Map<String, dynamic>? a,
    Map<String, dynamic>? b,
  ) {
    if (a == null || b == null) return false;
    return _helperShiftIdentityKey(a) == _helperShiftIdentityKey(b);
  }

  List<Map<String, dynamic>> _sortHelperShifts(
    List<Map<String, dynamic>> input,
  ) {
    final list = List<Map<String, dynamic>>.from(input);
    list.sort((a, b) {
      final da = (_helperShiftDate(a)).trim();
      final db = (_helperShiftDate(b)).trim();
      final sa = (_helperShiftStart(a)).trim();
      final sb = (_helperShiftStart(b)).trim();
      final ca = (_helperShiftClinicName(a)).trim();
      final cb = (_helperShiftClinicName(b)).trim();

      final dCmp = da.compareTo(db);
      if (dCmp != 0) return dCmp;

      final sCmp = sa.compareTo(sb);
      if (sCmp != 0) return sCmp;

      return ca.compareTo(cb);
    });
    return list;
  }

  List<Map<String, dynamic>> _dedupeHelperShiftList(
    List<Map<String, dynamic>> input,
  ) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final raw in input) {
      final item = Map<String, dynamic>.from(raw);
      final key = _helperShiftIdentityKey(item);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(item);
    }
    return out;
  }

  Map<String, dynamic>? _pickHelperShiftFromCandidates(
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) return null;
    if (items.length == 1) return items.first;

    final selected = _selectedHelperShift;
    if (selected != null) {
      for (final item in items) {
        if (_sameShiftIdentity(item, selected)) return item;
      }
    }

    final sameClinic = _clinicId.trim();
    if (sameClinic.isNotEmpty) {
      for (final item in items) {
        final cid =
            (item['clinicId'] ??
                    item['clinic']?['_id'] ??
                    item['clinic']?['id'] ??
                    '')
                .toString()
                .trim();
        if (cid.isNotEmpty && cid == sameClinic) return item;
      }
    }

    return null;
  }

  void _applySelectedHelperShift(
    Map<String, dynamic>? shift, {
    bool touchedByUser = false,
    String runtimeSelectionMode = '',
  }) {
    if (!mounted) return;
    setState(() {
      _selectedHelperShift =
          shift == null ? null : Map<String, dynamic>.from(shift);
      if (touchedByUser) _helperShiftTouchedByUser = true;
      if (runtimeSelectionMode.trim().isNotEmpty) {
        _helperRuntimeShiftSelectionMode = runtimeSelectionMode.trim();
      }
    });
  }

  String _helperShiftSummaryLine() {
    if (_helperShiftLoading) return 'กำลังโหลดกะงานของวันนี้';
    if (_helperShiftErr.trim().isNotEmpty) return _helperShiftErr.trim();

    if (_helperTodayShifts.isEmpty) {
      return 'วันนี้ยังไม่พบกะงานสำหรับการสแกน';
    }

    if (_selectedHelperShift == null) {
      if (_helperTodayShifts.length == 1) {
        return 'พบกะงาน 1 รายการ กรุณาตรวจสอบก่อนสแกน';
      }
      return 'พบ ${_helperTodayShifts.length} กะงาน กรุณาเลือกกะก่อนสแกน';
    }

    final mode = _helperRuntimeShiftSelectionMode.trim();
    if (mode == 'single_auto') {
      return 'ระบบเลือกกะให้อัตโนมัติ • $_selectedHelperShiftLabel';
    }
    if (mode == 'time_auto') {
      return 'ระบบเลือกกะตามช่วงเวลา • $_selectedHelperShiftLabel';
    }

    return _selectedHelperShiftLabel;
  }

  Future<void> _showHelperShiftPicker() async {
    if (!_isHelper) return;
    if (_helperTodayShifts.isEmpty) {
      _snack('วันนี้ยังไม่พบกะงานสำหรับการสแกน');
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _helperTodayShifts.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return const ListTile(
                  title: Text(
                    'เลือกกะที่จะใช้สแกนลายนิ้วมือ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'กรุณาเลือกกะที่กำลังทำงานอยู่จริง เพื่อให้ระบบส่ง shiftId ถูกต้อง',
                  ),
                );
              }

              final sh = _helperTodayShifts[i - 1];
              final isSelected = _sameShiftIdentity(sh, _selectedHelperShift);
              final clinic = _helperShiftClinicName(sh);
              final title = _helperShiftTitle(sh);
              final date = _helperShiftDate(sh);
              final start = _helperShiftStart(sh);
              final end = _helperShiftEnd(sh);

              final subtitleParts = <String>[];
              if (title.isNotEmpty && title != clinic) subtitleParts.add(title);
              if (date.isNotEmpty) subtitleParts.add(date);
              if (start.isNotEmpty || end.isNotEmpty) {
                subtitleParts.add(
                  '${start.isEmpty ? '--:--' : start} - ${end.isEmpty ? '--:--' : end}',
                );
              }

              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(clinic.isEmpty ? 'กะงาน' : clinic),
                subtitle: subtitleParts.isEmpty
                    ? null
                    : Text(subtitleParts.join(' • ')),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(ctx, sh),
              );
            },
          ),
        );
      },
    );

    if (selected == null) return;

    _applySelectedHelperShift(
      selected,
      touchedByUser: true,
      runtimeSelectionMode: 'manual_picker',
    );
    _snack('เลือกกะเรียบร้อยแล้ว');

    if (_attendancePremiumEnabled && !_attBusy) {
      await _refreshAttendanceToday(silent: true);
    }
  }

  Future<void> _loadHelperTodayShifts({bool silent = false}) async {
    if (!_isHelper) return;
    if (_ctxLoading) return;

    if (!silent && mounted) {
      setState(() {
        _helperShiftLoading = true;
        _helperShiftErr = '';
      });
    } else if (mounted && _helperShiftErr.isNotEmpty) {
      setState(() {
        _helperShiftErr = '';
      });
    }

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) throw Exception('no token');

      final headers = _authHeaders(token);
      final workDate = _todayYmd();

      final candidates = <Uri>[
        _payrollUri('/shifts', qs: {'date': workDate}),
        _payrollUri('/api/shifts', qs: {'date': workDate}),
        _payrollUri('/shift-needs/my-shifts', qs: {'workDate': workDate}),
        _payrollUri('/api/shift-needs/my-shifts', qs: {'workDate': workDate}),
        _payrollUri('/shift-needs/my-shifts', qs: {'date': workDate}),
        _payrollUri('/api/shift-needs/my-shifts', qs: {'date': workDate}),
      ];

      http.Response? successRes;

      for (final uri in candidates) {
        try {
          final res = await _tryGet(uri, headers: headers);
          if (res.statusCode == 404) continue;
          if (res.statusCode == 401) throw Exception('unauthorized');
          if (res.statusCode == 403) throw Exception('forbidden');

          if (res.statusCode == 200) {
            successRes = res;
            break;
          }
        } catch (e) {
          if (uri == candidates.last) rethrow;
        }
      }

      List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

      if (successRes != null) {
        final decoded = jsonDecode(successRes.body);

        dynamic source = decoded;
        if (decoded is Map) {
          if (decoded['items'] is List) {
            source = decoded['items'];
          } else if (decoded['data'] is List) {
            source = decoded['data'];
          } else if (decoded['results'] is List) {
            source = decoded['results'];
          } else if (decoded['rows'] is List) {
            source = decoded['rows'];
          } else if (decoded['shifts'] is List) {
            source = decoded['shifts'];
          } else if (decoded['needs'] is List) {
            source = decoded['needs'];
          } else if (decoded['runtime'] is Map &&
              (decoded['runtime'] as Map)['shift'] is Map) {
            source = [
              Map<String, dynamic>.from(
                (decoded['runtime'] as Map)['shift'] as Map,
              ),
            ];
          } else if (decoded['availableShifts'] is List) {
            source = decoded['availableShifts'];
          }
        }

        if (source is List) {
          items = source
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      items = _dedupeHelperShiftList(items);
      items = _sortHelperShifts(items);

      final picked = _pickHelperShiftFromCandidates(items);

      if (!mounted) return;
      setState(() {
        _helperTodayShifts = items;
        _selectedHelperShift = picked == null
            ? (items.length == 1 ? items.first : null)
            : Map<String, dynamic>.from(picked);
        _helperShiftLoading = false;
        _helperShiftErr = '';
        if (items.length == 1 && _selectedHelperShift != null) {
          _helperRuntimeShiftSelectionMode = 'single_auto';
        } else if (_selectedHelperShift == null) {
          _helperRuntimeShiftSelectionMode = '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _helperShiftLoading = false;
        _helperShiftErr = 'ไม่สามารถโหลดกะงานของวันนี้ได้';
        _helperTodayShifts = <Map<String, dynamic>>[];
        _selectedHelperShift = null;
        _helperRuntimeShiftSelectionMode = '';
      });
    }
  }

  bool _helperCanProceedScan() {
    if (!_isHelper) return true;

    if (_helperShiftLoading) {
      _snack('กำลังโหลดกะงานของวันนี้ กรุณารอสักครู่');
      return false;
    }

    if (_helperTodayShifts.isEmpty) {
      final msg = _helperShiftErr.trim().isNotEmpty
          ? _helperShiftErr.trim()
          : 'วันนี้ยังไม่พบกะงานสำหรับการสแกน';
      _snack(msg);
      return false;
    }

    if (_selectedHelperShift == null || _selectedHelperShiftId.isEmpty) {
      _snack('กรุณาเลือกกะก่อนสแกนลายนิ้วมือ');
      return false;
    }

    return true;
  }

  void _setAttendanceUiPhase(
    _AttendanceUiPhase phase, {
    String progressText = '',
    bool clearErr = false,
  }) {
    if (!mounted) return;
    setState(() {
      _attUiPhase = phase;
      _attProgressText = progressText;
      if (clearErr) _attErr = '';
      _bioLoading = phase == _AttendanceUiPhase.checkingInBio ||
          phase == _AttendanceUiPhase.checkingOutBio;
      _attPosting = phase == _AttendanceUiPhase.checkingInSubmit ||
          phase == _AttendanceUiPhase.checkingOutSubmit;
    });
  }

  void _resetAttendanceUiPhase() {
    _slowNetworkTimer?.cancel();
    _slowNetworkTimer = null;
    if (!mounted) return;
    setState(() {
      _attUiPhase = _AttendanceUiPhase.idle;
      _attProgressText = '';
      _showSlowNetworkHint = false;
      _bioLoading = false;
      _attPosting = false;
      _attLocationLoading = false;
    });
  }

  void _startSlowNetworkHint() {
    _slowNetworkTimer?.cancel();
    _showSlowNetworkHint = false;
    _slowNetworkTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_attBusy) return;
      setState(() {
        _showSlowNetworkHint = true;
      });
    });
  }

  Future<String?> _getTokenAny() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty && t != 'null') return t;
    } catch (_) {}

    const keys = [
      'jwtToken',
      'token',
      'authToken',
      'userToken',
      'jwt_token',
      'accessToken',
      'access_token',
    ];
    final prefs = await SharedPreferences.getInstance();
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      String p = parts[1];
      p = p.replaceAll('-', '+').replaceAll('_', '/');
      while (p.length % 4 != 0) {
        p += '=';
      }
      final decoded = utf8.decode(base64Url.decode(p));
      final obj = jsonDecode(decoded);
      if (obj is Map) return Map<String, dynamic>.from(obj);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPremiumFlags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_kPremiumAttendanceKey) ?? false;
      if (!mounted) return;
      setState(() {
        _premiumAttendanceEnabled = v;
        _premiumLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _premiumAttendanceEnabled = false;
        _premiumLoading = false;
      });
    }
  }

  Future<void> _setPremiumAttendanceEnabled(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPremiumAttendanceKey, v);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _premiumAttendanceEnabled = v;
    });

    if (!v) return;

    if (_isAttendanceUser) {
      if (_isHelper) {
        await _loadHelperTodayShifts();
      }
      await _refreshAttendanceToday();
    }
  }

  bool get _isClinic =>
      _role == 'admin' || _role == 'clinic' || _role == 'clinic_admin';
  bool get _isEmployee =>
      _role == 'employee' || _role == 'staff' || _role == 'emp';
  bool get _isHelper => _role == 'helper';
  bool get _isAttendanceUser => _isEmployee || _isHelper;

  bool _featureEnabled(String key, {bool fallback = false}) {
    final v = _features[key];
    if (v is bool) return v;
    return fallback;
  }

  bool get _hasBackendPolicy => _policy.isNotEmpty;

  bool get _attendancePremiumEnabled {
    if (_hasBackendPolicy) {
      return _featureEnabled('fingerprintAttendance', fallback: true);
    }
    return _premiumAttendanceEnabled;
  }

  bool get _policyHumanReadableEnabled {
    if (_hasBackendPolicy) {
      return _featureEnabled('policyHumanReadable', fallback: true);
    }
    return true;
  }

  String _hhmm(dynamic v, {String fallback = '--:--'}) {
    final s = (v ?? '').toString().trim();
    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return s;
    return fallback;
  }

  List<String> _buildRoleAwarePolicyLines(Map<String, dynamic> p) {
    final lines = <String>[];

    final realTimeOnly = p['realTimeAttendanceOnly'] == true;
    final manualNeedApproval = p['manualAttendanceRequireApproval'] == true;
    final manualReasonRequired = p['manualReasonRequired'] == true;
    final employeeOnlyOt = p['employeeOnlyOt'] == true;
    final requireOtApproval = p['requireOtApproval'] == true;
    final lockAfterClose = p['lockAfterPayrollClose'] == true;

    final otWindowStart = _hhmm(p['otWindowStart'], fallback: '');
    final otWindowEnd = _hhmm(p['otWindowEnd'], fallback: '');

    if (_isHelper) {
      lines.add('ค่าตอบแทนของผู้ช่วยจะคำนวณตามเวลาทำงานจริง');
      if (employeeOnlyOt) {
        lines.add('ผู้ช่วยไม่มี OT แยกต่างหาก ระบบจะคำนวณตามเวลาทำงานจริง');
      }
      if (realTimeOnly) {
        lines.add('การลงเวลาทำงานต้องบันทึกตามเวลาจริง');
      }
      if (manualNeedApproval) {
        lines.add('หากลืมลงเวลา ต้องส่งคำขอแก้ไขเวลาและรอการอนุมัติ');
      }
      if (manualReasonRequired) {
        lines.add('การขอแก้ไขเวลาทำงานจำเป็นต้องระบุเหตุผล');
      }
      if (lockAfterClose) {
        lines.add('เมื่อปิดรอบเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้');
      }
      return lines;
    }

    if (_isEmployee) {
      if (realTimeOnly) {
        lines.add('การลงเวลาทำงานต้องบันทึกตามเวลาจริง');
      }
      if (otWindowStart.isNotEmpty && otWindowEnd.isNotEmpty) {
        lines.add('ระบบจะคำนวณ OT เฉพาะช่วงเวลา $otWindowStart - $otWindowEnd');
        lines.add('เวลานอกช่วงดังกล่าวจะไม่นับรวมเป็น OT');
      }
      if (requireOtApproval) {
        lines.add('OT จะนำไปคำนวณเงินได้ต่อเมื่อได้รับการอนุมัติแล้ว');
      }
      if (manualNeedApproval) {
        lines.add('หากลืมลงเวลา ต้องส่งคำขอแก้ไขเวลาและรอคลินิกอนุมัติ');
      }
      if (manualReasonRequired) {
        lines.add('การขอแก้ไขเวลาทำงานจำเป็นต้องระบุเหตุผล');
      }
      if (lockAfterClose) {
        lines.add('เมื่อปิดรอบเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้');
      }
      if (_policyRequireLocation || _isEmployee) {
        lines.add(_locationRuleText());
      }
      return lines;
    }

    if (otWindowStart.isNotEmpty && otWindowEnd.isNotEmpty) {
      lines.add('คลินิกกำหนดช่วงเวลา OT ไว้ที่ $otWindowStart - $otWindowEnd');
    }
    if (requireOtApproval) {
      lines.add('OT ต้องได้รับการอนุมัติก่อนจึงจะเข้าสู่ระบบเงินเดือน');
    }
    if (manualNeedApproval) {
      lines.add('การแก้ไขเวลาทำงานต้องผ่านการอนุมัติ');
    }
    if (lockAfterClose) {
      lines.add('เมื่อปิดรอบเงินเดือนแล้ว จะไม่สามารถแก้ไขเวลาย้อนหลังได้');
    }

    return lines;
  }

  void _applyPolicyFromMap(Map<String, dynamic> p) {
    final featuresAny = p['features'];
    final features = (featuresAny is Map)
        ? Map<String, dynamic>.from(featuresAny)
        : <String, dynamic>{};

    final lines = _buildRoleAwarePolicyLines(p);

    if (!mounted) return;
    setState(() {
      _policy = p;
      _features = features;
      _policyLines = lines;
      _policyErr = '';
    });
  }

  Future<void> _bootstrapContext() async {
    if (!mounted) return;
    setState(() {
      _ctxLoading = true;
      _ctxErr = '';
    });

    await _loadPremiumFlags();

    try {
      await AppContextResolver.loadFromPrefs();

      String role = _norm(AppContext.role);
      String uid = (AppContext.userId).trim();
      String cid = (AppContext.clinicId).trim();

      String sid = '';
      final token = await _getTokenAny();
      if (token != null && token.isNotEmpty) {
        final payload = _decodeJwtPayload(token);
        if (payload != null) {
          role = role.isNotEmpty ? role : _norm('${payload['role'] ?? ''}');
          uid = uid.isNotEmpty ? uid : ('${payload['userId'] ?? ''}').trim();
          cid = cid.isNotEmpty ? cid : ('${payload['clinicId'] ?? ''}').trim();
          sid = ('${payload['staffId'] ?? ''}').trim();
        }
      }

      if (role.isEmpty || uid.isEmpty) {
        throw Exception('context missing');
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _userId = uid;
        _clinicId = cid;
        _staffId = sid;
        _ctxLoading = false;
      });

      if (!_didSetInitialTab) {
        _didSetInitialTab = true;
      }

      await _loadClinicPolicy();
      await _loadUrgentNeeds();

      if (_isHelper && _attendancePremiumEnabled) {
        await _loadHelperTodayShifts();
      }

      if (_isAttendanceUser && _attendancePremiumEnabled) {
        await _refreshAttendanceToday();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ctxErr = _friendlyAuthError(e);
        _ctxLoading = false;
      });
    }
  }

  Uri _payrollUri(String path, {Map<String, String>? qs}) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    return (qs == null) ? uri : uri.replace(queryParameters: qs);
  }

  Future<http.Response> _tryGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
  }

  Future<http.Response> _tryPost(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) async {
    return http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));
  }

  List<Map<String, dynamic>> _decodeNeedList(dynamic decoded) {
    dynamic listAny = decoded;
    if (decoded is Map) {
      if (decoded['items'] is List) {
        listAny = decoded['items'];
      } else if (decoded['data'] is List) {
        listAny = decoded['data'];
      } else if (decoded['results'] is List) {
        listAny = decoded['results'];
      } else if (decoded['needs'] is List) {
        listAny = decoded['needs'];
      }
    }
    if (listAny is! List) return [];
    return listAny
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _loadClinicPolicy() async {
    if (_ctxLoading) return;

    if (!mounted) return;
    setState(() {
      _policyLoading = true;
      _policyErr = '';
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        throw Exception('no token');
      }

      final headers = _authHeaders(token);
      final candidates = <String>[
        '/clinic-policy/me',
        '/api/clinic-policy/me',
      ];

      http.Response? last;

      for (final p in candidates) {
        final u = _payrollUri(p);
        final res = await _tryGet(u, headers: headers);
        last = res;

        if (res.statusCode == 404) continue;
        if (res.statusCode == 401) throw Exception('unauthorized');
        if (res.statusCode == 403) throw Exception('forbidden');

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          Map<String, dynamic> m = {};
          if (decoded is Map) m = Map<String, dynamic>.from(decoded);

          final policyAny = (m['policy'] is Map) ? m['policy'] : m;
          final pMap = (policyAny is Map)
              ? Map<String, dynamic>.from(policyAny)
              : <String, dynamic>{};

          _applyPolicyFromMap(pMap);

          if (!mounted) return;
          setState(() {
            _policyLoading = false;
            _policyErr = '';
          });
          return;
        }

        if (res.statusCode >= 400 && res.statusCode < 500) break;
      }

      if (!mounted) return;
      setState(() {
        _policyLoading = false;
        _policyErr = (last == null)
            ? 'ไม่สามารถเชื่อมต่อได้'
            : 'ไม่สามารถโหลดเงื่อนไขของคลินิกได้';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _policyLoading = false;
        _policyErr = _friendlyAuthError(e);
      });
    }
  }

  Future<void> _loadUrgentNeeds() async {
    if (_ctxLoading) return;

    if (_urgentLoading) {
      print('[URGENT] skipped because loading');
      return;
    }

    if (!mounted) return;
    setState(() {
      _urgentLoading = true;
      _urgentErr = '';
      _urgentCount = 0;
      _urgentFirst = null;
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) {
        throw Exception('no token');
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      http.Response res;
      Uri u;

      if (_isHelper) {
        u = _payrollUri('/shift-needs/open');
        res = await _tryGet(u, headers: headers);

        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
        if (res.statusCode == 404) {
          u = _payrollUri('/shift-needs', qs: {'status': 'open'});
          res = await _tryGet(u, headers: headers);
        }
        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs', qs: {'status': 'open'});
          res = await _tryGet(u, headers: headers);
        }
      } else if (_isClinic) {
        final cid = _clinicId.trim();
        if (cid.isEmpty) {
          throw Exception('missing clinic');
        }

        u = _payrollUri('/shift-needs', qs: {
          'status': 'open',
          'clinicId': cid,
        });
        res = await _tryGet(u, headers: headers);

        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs', qs: {
            'status': 'open',
            'clinicId': cid,
          });
          res = await _tryGet(u, headers: headers);
        }

        if (res.statusCode == 404) {
          u = _payrollUri('/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
        if (res.statusCode == 404) {
          u = _payrollUri('/api/shift-needs/open');
          res = await _tryGet(u, headers: headers);
        }
      } else {
        if (!mounted) return;
        setState(() {
          _urgentErr = '';
          _urgentCount = 0;
          _urgentFirst = null;
        });
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('bad status ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      final list = _decodeNeedList(decoded);

      final openOnly = list.where((n) {
        final status = (n['status'] ?? '').toString().toLowerCase().trim();
        return status.isEmpty || status == 'open';
      }).toList();

      if (!mounted) return;
      setState(() {
        _urgentErr = '';
        _urgentCount = openOnly.length;
        _urgentFirst = openOnly.isNotEmpty ? openOnly.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _urgentErr = _friendlyAuthError(e);
        _urgentCount = 0;
        _urgentFirst = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _urgentLoading = false;
      });
    }
  }

  Future<void> _activeRefreshUrgent() async {
    if (!mounted) return;

    if (_activeRefreshing) {
      _snack('กำลังอัปเดตข้อมูล กรุณารอสักครู่');
      return;
    }

    setState(() {
      _activeRefreshing = true;
    });

    _snack('กำลังอัปเดตข้อมูล กรุณารอสักครู่');

    try {
      if (_ctxLoading || _role.trim().isEmpty) {
        await _bootstrapContext();
      } else {
        await _loadClinicPolicy();
        await _loadUrgentNeeds();

        if (_isHelper && _attendancePremiumEnabled) {
          await _loadHelperTodayShifts(silent: true);
        }
        if (_isAttendanceUser && _attendancePremiumEnabled && !_attBusy) {
          await _refreshAttendanceToday();
        }
      }

      if (!mounted) return;

      if (_ctxErr.isNotEmpty) {
        _snack(_ctxErr);
        return;
      }

      if (_urgentErr.isNotEmpty) {
        _snack(_urgentErr);
        return;
      }

      _snack('อัปเดตข้อมูลล่าสุดเรียบร้อยแล้ว');
    } catch (e) {
      if (!mounted) return;
      _snack('ไม่สามารถอัปเดตข้อมูลได้ กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (!mounted) return;
      setState(() {
        _activeRefreshing = false;
      });
    }
  }

  Future<void> _refreshUrgentCardOnly() async {
    if (_urgentLoading || _activeRefreshing) {
      _snack('กำลังอัปเดตประกาศงาน กรุณารอสักครู่');
      return;
    }

    _snack('กำลังอัปเดตประกาศงาน กรุณารอสักครู่');
    await _loadUrgentNeeds();

    if (!mounted) return;

    if (_urgentErr.isNotEmpty) {
      _snack(_urgentErr);
      return;
    }

    _snack('อัปเดตประกาศงานล่าสุดเรียบร้อยแล้ว');
  }

  Future<void> _logout() async {
    _tapLog('LOGOUT');

    try {
      await AuthStorage.clearToken();
    } catch (_) {}
    try {
      await AppContextResolver.clear();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.authGate,
      (_) => false,
    );
  }

  Future<void> _openTrustScoreFromHome() async {
    _tapLog('OPEN_TRUSTSCORE');

    if (_ctxLoading) return;

    if (!_isClinic) {
      _snack('เมนูนี้สำหรับคลินิกเท่านั้น');
      return;
    }

    final ok = await _askClinicPinAndVerify();
    if (ok != true) return;

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TrustScoreLookupScreen()),
    );
  }

  Future<void> _openHelperMarketplaceForClinicTrustScore() async {
    _tapLog('OPEN_HELPER_MARKETPLACE_FOR_TRUSTSCORE');

    if (_ctxLoading) return;

    if (!_isClinic) {
      _snack('เมนูนี้สำหรับคลินิกเท่านั้น');
      return;
    }

    final ok = await _askClinicPinAndVerify();
    if (ok != true) return;

    if (!mounted) return;

    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const HelperMarketplaceScreen(),
      ),
    );

    if (!mounted || selected == null) return;

    final helperName = ((selected['fullName'] ??
                selected['name'] ??
                selected['phone'] ??
                selected['staffId'] ??
                selected['userId'] ??
                'ผู้ช่วย')
            .toString())
        .trim();

    _snack('เลือก $helperName แล้ว');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrustScoreLookupScreen(
          initialHelper: selected,
          initialStaffId: (selected['staffId'] ?? '').toString(),
          initialQuery:
              (selected['fullName'] ?? selected['name'] ?? '').toString(),
        ),
      ),
    );
  }

  Future<bool?> _askClinicPinAndVerify() async {
    final ctrl = TextEditingController();
    bool loading = false;
    String errText = '';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            Future<void> verify() async {
              final pin = ctrl.text.trim();
              if (pin.isEmpty) {
                setSt(() => errText = 'กรุณากรอก PIN');
                return;
              }

              FocusScope.of(ctx).unfocus();

              setSt(() {
                loading = true;
                errText = '';
              });

              try {
                final ok = await AuthService.verifyPin(pin);
                if (!ctx.mounted) return;

                if (ok) {
                  Navigator.of(ctx, rootNavigator: true).pop(true);
                } else {
                  setSt(() => errText = 'PIN ไม่ถูกต้อง');
                }
              } catch (_) {
                if (!ctx.mounted) return;
                setSt(() => errText = 'ไม่สามารถตรวจสอบ PIN ได้');
              } finally {
                if (ctx.mounted) setSt(() => loading = false);
              }
            }

            return AlertDialog(
              title: const Text('ยืนยันตัวตนคลินิก'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'กรุณากรอก PIN ของคลินิกเพื่อดูคะแนนผู้ช่วย',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'PIN คลินิก',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => verify(),
                  ),
                  if (errText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      errText,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(ctx, rootNavigator: true).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: loading ? null : verify,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      ctrl.dispose();
    });

    return result;
  }

  Future<void> _openMyClinic() async {
    _tapLog('OPEN_MY_CLINIC');

    if (_clinicId.trim().isEmpty || _userId.trim().isEmpty) {
      _snack('ไม่พบข้อมูลบัญชี กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicHomeScreen(
          clinicId: _clinicId.trim(),
          userId: _userId.trim(),
        ),
      ),
    );
  }

  Future<void> _openMyHelper() async {
    _tapLog('OPEN_MY_HELPER');

    if (_userId.trim().isEmpty) {
      _snack('ไม่พบข้อมูลบัญชี กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HelperHomeScreen(
          clinicId: _clinicId.trim(),
          userId: _userId.trim(),
          staffId: _staffId.trim(),
        ),
      ),
    );
  }

  Future<void> _openClinicNeedsMarket() async {
    _tapLog('OPEN_CLINIC_MARKET');

    if (_ctxLoading) return;

    if (!_isClinic) {
      _snack('เมนูนี้สำหรับคลินิกเท่านั้น');
      return;
    }
    if (_clinicId.trim().isEmpty) {
      _snack('ไม่พบข้อมูลคลินิก กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClinicShiftNeedListScreen(clinicId: _clinicId.trim()),
      ),
    );
  }

  Future<void> _openHelperOpenNeeds() async {
    _tapLog('OPEN_HELPER_OPEN_NEEDS');

    if (_ctxLoading) return;

    if (!_isHelper) {
      _snack('เมนูนี้สำหรับผู้ช่วยเท่านั้น');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelperOpenNeedsScreen()),
    );
  }

  String _bioUserMessageFromCode(String code) {
    final c = code.toLowerCase().trim();

    if (c.contains('notenrolled')) {
      return 'อุปกรณ์นี้ยังไม่ได้ตั้งค่าลายนิ้วมือ กรุณาตั้งค่าในเครื่องก่อนใช้งาน';
    }
    if (c.contains('passcodenotset')) {
      return 'กรุณาตั้งรหัสล็อกหน้าจอก่อนใช้งาน';
    }
    if (c.contains('notavailable')) {
      return 'ระบบยืนยันตัวตนยังไม่พร้อมใช้งาน กรุณาลองใหม่';
    }
    if (c.contains('lockedout')) {
      return 'สแกนผิดหลายครั้ง ระบบถูกล็อกชั่วคราว กรุณาปลดล็อกด้วยรหัสหน้าจอก่อนแล้วลองใหม่';
    }
    if (c.contains('permanentlylockedout')) {
      return 'ระบบถูกล็อกเพื่อความปลอดภัย กรุณาปลดล็อกด้วยรหัสหน้าจอ หรือตั้งค่าชีวมิติใหม่';
    }
    if (c.contains('usercanceled') || c.contains('usercancel')) {
      return 'ยกเลิกการยืนยันตัวตน';
    }
    if (c.contains('authentication_failed')) {
      return 'ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่';
    }
    if (c.contains('biometric_only_not_supported')) {
      return 'อุปกรณ์นี้ไม่รองรับการยืนยันตัวตนแบบชีวมิติเพียงอย่างเดียว';
    }

    return 'ยืนยันตัวตนไม่สำเร็จ (BIO ERROR: $code)';
  }

  Future<bool> _hasFingerprintAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;

      final canCheck = await _localAuth.canCheckBiometrics;
      final types = await _localAuth.getAvailableBiometrics();

      if (!canCheck && types.isEmpty) return false;

      if (types.contains(BiometricType.fingerprint)) return true;
      if (types.contains(BiometricType.face)) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _biometricAuthenticate() async {
    try {
      print('[BIO] START');
      final okToTry = await _hasFingerprintAvailable();
      print('[BIO] hasFingerprintAvailable=$okToTry');

      if (!okToTry) {
        _snack('อุปกรณ์นี้ไม่รองรับการยืนยันตัวตนด้วยลายนิ้วมือ');
        return false;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: 'ยืนยันตัวตนด้วยลายนิ้วมือเพื่อบันทึกเวลาทำงาน',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      print('[BIO] authenticate result=$ok');

      if (!ok) {
        _snack('ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่');
      }

      return ok;
    } on PlatformException catch (e) {
      print('[BIO] PlatformException code=${e.code} message=${e.message}');
      final msg = _bioUserMessageFromCode(e.code);
      _snack(msg);
      return false;
    } catch (e) {
      print('[BIO] ERROR $e');
      _snack('ยืนยันตัวตนไม่สำเร็จ กรุณาลองใหม่');
      return false;
    }
  }

  Map<String, String> _authHeaders(String token) => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _attendancePayload({
    String? reasonCode,
    String? reasonText,
    String? note,
    Position? position,
  }) {
    final payload = <String, dynamic>{
      'workDate': _todayYmd(),
      'biometricVerified': true,
      'method': 'biometric',
    };

    final helperShiftId = _selectedHelperShiftId;
    if (_isHelper && helperShiftId.isNotEmpty) {
      payload['shiftId'] = helperShiftId;
    }

    if (!_isHelper && _clinicId.trim().isNotEmpty) {
      payload['clinicId'] = _clinicId.trim();
    }

    if (_staffId.trim().isNotEmpty) {
      payload['staffId'] = _staffId.trim();
    }

    if ((reasonCode ?? '').trim().isNotEmpty) {
      payload['reasonCode'] = reasonCode!.trim();
    }

    if ((reasonText ?? '').trim().isNotEmpty) {
      payload['reasonText'] = reasonText!.trim();
    }

    if ((note ?? '').trim().isNotEmpty) {
      payload['note'] = note!.trim();
    }

    final withLocation = _appendAttendanceLocation(
      payload,
      position: position,
    );

    print('[ATTENDANCE][PAYLOAD] $withLocation');
    return withLocation;
  }

  Map<String, dynamic> _decodeBodyMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _extractApiMessage(http.Response res) {
    final decoded = _decodeBodyMap(res.body);
    final msg = (decoded['message'] ??
            decoded['error'] ??
            decoded['msg'] ??
            decoded['detail'] ??
            '')
        .toString()
        .trim();
    return msg;
  }

  String _extractApiCode(http.Response res) {
    final decoded = _decodeBodyMap(res.body);
    return (decoded['code'] ?? '').toString().trim();
  }

  bool _sameYmdFromAny(dynamic v, String ymd) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return false;
    if (s.length >= 10) {
      return s.substring(0, 10) == ymd;
    }
    return false;
  }

  bool _hasValue(dynamic v) => (v ?? '').toString().trim().isNotEmpty;

  bool _isTodaySession(Map<String, dynamic> s) {
    final today = _todayYmd();
    final workDate = s['workDate'] ?? s['date'] ?? s['day'];
    final ci = s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime'];
    final co = s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime'];

    return _sameYmdFromAny(workDate, today) ||
        _sameYmdFromAny(ci, today) ||
        _sameYmdFromAny(co, today);
  }

  bool _sessionLooksOpen(Map<String, dynamic> s) {
    final status = (s['status'] ?? '').toString().trim().toLowerCase();
    final hasIn =
        _hasValue(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']);
    final hasOut =
        _hasValue(s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime']);

    if (status == 'open') return true;
    if (status == 'working') return true;
    if (status == 'checked_in') return true;
    if (status == 'in_progress') return true;
    if (status == 'closed' || status == 'cancelled' || status == 'completed') {
      return false;
    }

    return hasIn && !hasOut;
  }

  bool _sessionLooksClosed(Map<String, dynamic> s) {
    final status = (s['status'] ?? '').toString().trim().toLowerCase();
    final hasIn =
        _hasValue(s['checkInAt'] ?? s['checkinAt'] ?? s['checkInTime']);
    final hasOut =
        _hasValue(s['checkOutAt'] ?? s['checkoutAt'] ?? s['checkOutTime']);

    if (status == 'closed') return true;
    if (status == 'completed') return true;
    if (status == 'checked_out') return true;
    if (status == 'done') return true;
    if (status == 'open' || status == 'working' || status == 'checked_in') {
      return false;
    }

    return hasIn && hasOut;
  }

  bool _sessionMatchesSelectedHelperShift(Map<String, dynamic> s) {
    if (!_isHelper) return true;

    final selectedShiftId = _selectedHelperShiftId;
    if (selectedShiftId.isEmpty) return true;

    final sessionShiftId =
        (s['shiftId'] ?? s['shift']?['_id'] ?? s['shift']?['id'] ?? '')
            .toString()
            .trim();

    return sessionShiftId.isNotEmpty && sessionShiftId == selectedShiftId;
  }

  List<Map<String, dynamic>> _extractAttendanceList(dynamic decoded) {
    List<Map<String, dynamic>> list = [];

    if (decoded is Map) {
      final dataAny = decoded['data'];
      if (dataAny is List) {
        list = dataAny
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (decoded['items'] is List) {
        list = (decoded['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (decoded['results'] is List) {
        list = (decoded['results'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (decoded['sessions'] is List) {
        list = (decoded['sessions'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (decoded['rows'] is List) {
        list = (decoded['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } else if (decoded is List) {
      list = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (_isHelper && _selectedHelperShiftId.isNotEmpty) {
      list = list.where(_sessionMatchesSelectedHelperShift).toList();
    }

    return list;
  }

  Map<String, dynamic>? _mapFromAny(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  Map<String, dynamic>? _pickFirstMap(List<dynamic> values) {
    for (final v in values) {
      final m = _mapFromAny(v);
      if (m != null && m.isNotEmpty) return m;
    }
    return null;
  }

  bool _previewHasCheckInEvidence(Map<String, dynamic> data) {
    final attendance = _mapFromAny(data['attendance']) ?? <String, dynamic>{};
    final runtime = _mapFromAny(data['runtime']) ?? <String, dynamic>{};
    final summary = _mapFromAny(data['summary']) ?? <String, dynamic>{};

    final topSession = _pickFirstMap([
      data['session'],
      data['todaySession'],
      data['currentSession'],
      data['openSession'],
      attendance['session'],
      attendance['todaySession'],
      attendance['currentSession'],
      attendance['openSession'],
      runtime['session'],
      runtime['currentSession'],
      runtime['openSession'],
    ]);

    final hasTopSessionCheckIn = topSession != null &&
        (_hasValue(topSession['checkInAt']) ||
            _hasValue(topSession['checkinAt']) ||
            _hasValue(topSession['checkInTime']) ||
            _sessionLooksOpen(topSession) ||
            _sessionLooksClosed(topSession));

    final workedMinutes = summary['workedMinutes'];
    final workedMinutesPositive = workedMinutes is num && workedMinutes > 0;

    return _isTruthy(data['checkedIn']) ||
        _isTruthy(data['hasCheckIn']) ||
        _isTruthy(data['isCheckedIn']) ||
        _isTruthy(data['working']) ||
        _isTruthy(attendance['checkedIn']) ||
        _isTruthy(attendance['hasCheckIn']) ||
        _isTruthy(attendance['isCheckedIn']) ||
        _isTruthy(attendance['working']) ||
        _hasValue(data['checkInAt']) ||
        _hasValue(data['checkinAt']) ||
        _hasValue(data['checkInTime']) ||
        _hasValue(attendance['checkInAt']) ||
        _hasValue(attendance['checkinAt']) ||
        _hasValue(attendance['checkInTime']) ||
        hasTopSessionCheckIn ||
        workedMinutesPositive;
  }

  bool _previewHasCheckOutEvidence(Map<String, dynamic> data) {
    final attendance = _mapFromAny(data['attendance']) ?? <String, dynamic>{};
    final runtime = _mapFromAny(data['runtime']) ?? <String, dynamic>{};
    final summary = _mapFromAny(data['summary']) ?? <String, dynamic>{};

    final topSession = _pickFirstMap([
      data['session'],
      data['todaySession'],
      data['currentSession'],
      data['openSession'],
      attendance['session'],
      attendance['todaySession'],
      attendance['currentSession'],
      attendance['openSession'],
      runtime['session'],
      runtime['currentSession'],
      runtime['openSession'],
    ]);

    final hasTopSessionCheckOut = topSession != null &&
        (_hasValue(topSession['checkOutAt']) ||
            _hasValue(topSession['checkoutAt']) ||
            _hasValue(topSession['checkOutTime']) ||
            _sessionLooksClosed(topSession));

    final workedMinutes = summary['workedMinutes'];
    final workedMinutesPositive = workedMinutes is num && workedMinutes > 0;

    return _isTruthy(data['checkedOut']) ||
        _isTruthy(data['hasCheckOut']) ||
        _isTruthy(data['isCheckedOut']) ||
        _isTruthy(attendance['checkedOut']) ||
        _isTruthy(attendance['hasCheckOut']) ||
        _isTruthy(attendance['isCheckedOut']) ||
        _hasValue(data['checkOutAt']) ||
        _hasValue(data['checkoutAt']) ||
        _hasValue(data['checkOutTime']) ||
        _hasValue(attendance['checkOutAt']) ||
        _hasValue(attendance['checkoutAt']) ||
        _hasValue(attendance['checkOutTime']) ||
        hasTopSessionCheckOut ||
        (_isTruthy(data['completed']) || _isTruthy(attendance['completed'])) ||
        (workedMinutesPositive &&
            !_isTruthy(data['working']) &&
            !_isTruthy(attendance['working']) &&
            !_hasValue(data['checkOutBlockedReason']));
  }

  String _buildAttendanceStatusLine({
    required bool checkedIn,
    required bool checkedOut,
    required bool hasPendingManual,
    String message = '',
  }) {
    String line = message.trim();

    if (line.isEmpty) {
      if (hasPendingManual && !checkedIn && !checkedOut) {
        line = 'วันนี้มีคำขอแก้ไขเวลารอการอนุมัติ';
      } else if (checkedIn && checkedOut) {
        line = 'วันนี้เช็คอินและเช็คเอาท์เรียบร้อยแล้ว';
      } else if (checkedIn && !checkedOut) {
        line = 'วันนี้เช็คอินเรียบร้อยแล้ว (ยังไม่ได้เช็คเอาท์)';
      } else {
        line = 'วันนี้ยังไม่ได้เช็คอิน';
      }
    }

    if (_isHelper) {
      if (_helperTodayShifts.isEmpty) {
        return 'วันนี้ยังไม่พบกะงานสำหรับการสแกน';
      }
      if (_selectedHelperShift == null) {
        return 'กรุณาเลือกกะก่อนสแกนลายนิ้วมือ';
      }
      if (checkedIn && checkedOut) {
        return 'เช็คอินและเช็คเอาท์แล้วสำหรับกะที่เลือก';
      }
      if (checkedIn && !checkedOut && hasPendingManual) {
        return 'เช็คอินแล้วสำหรับกะที่เลือก • ยังไม่ได้เช็คเอาท์ • $_selectedHelperShiftLabel';
      }
      if (checkedIn && !checkedOut) {
        return 'เช็คอินแล้วสำหรับกะที่เลือก • $_selectedHelperShiftLabel';
      }
      if (hasPendingManual) {
        return 'มีคำขอแก้ไขเวลารออนุมัติสำหรับกะที่เลือก • $_selectedHelperShiftLabel';
      }
      return 'พร้อมสแกนสำหรับกะที่เลือก • $_selectedHelperShiftLabel';
    }

    if (checkedIn && !checkedOut && hasPendingManual) {
      return 'วันนี้เช็คอินเรียบร้อยแล้ว (ยังไม่ได้เช็คเอาท์) • มีคำขอแก้ไขเวลารอการอนุมัติ';
    }

    if (_attendanceNeedsLiveLocation && !checkedIn) {
      return 'ยังไม่ได้เช็คอิน • ${_locationRuleText()}';
    }

    return line;
  }

  bool _canOpenManualRequest({
    bool showSnack = true,
    bool helperShiftRequired = true,
  }) {
    if (_ctxLoading) {
      if (showSnack) {
        _snack('กำลังเตรียมข้อมูล กรุณาลองอีกครั้ง');
      }
      return false;
    }

    if (!_isAttendanceUser) {
      if (showSnack) {
        _snack('เมนูนี้สำหรับพนักงานหรือผู้ช่วยเท่านั้น');
      }
      return false;
    }

    if (!_attendancePremiumEnabled) {
      if (showSnack) {
        _snack('ฟีเจอร์นี้สำหรับแพ็กเกจพรีเมียม');
      }
      return false;
    }

    if (_openingManualRequestFlow) {
      if (showSnack) {
        _snack('กำลังเปิดหน้าคำขอแก้ไขเวลา กรุณารอสักครู่');
      }
      return false;
    }

    if (_isHelper && helperShiftRequired && !_helperCanProceedScan()) {
      return false;
    }

    return true;
  }

  Future<bool> _openManualAttendanceRequest({
    required String manualRequestType,
    String initialReasonCode = '',
    String initialReasonText = '',
    String initialMessage = '',
    bool isFixingPreviousPending = false,
    String previousSessionId = '',
    String previousWorkDate = '',
    String previousShiftId = '',
    String previousClinicName = '',
  }) async {
    if (!mounted) return false;
    if (!_canOpenManualRequest()) return false;

    _openingManualRequestFlow = true;
    try {
      final clinicNameForScreen = previousClinicName.trim().isNotEmpty
          ? previousClinicName.trim()
          : _attPreviousClinicName.trim().isNotEmpty
              ? _attPreviousClinicName.trim()
              : (_selectedHelperShift != null
                  ? _helperShiftClinicName(_selectedHelperShift!)
                  : '');

      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ManualAttendanceRequestScreen(
            role: _role,
            clinicId: _clinicId,
            userId: _userId,
            staffId: _staffId,
            initialClinicName: clinicNameForScreen,
            initialWorkDate: previousWorkDate.trim().isNotEmpty
                ? previousWorkDate.trim()
                : _todayYmd(),
            initialManualRequestType: manualRequestType,
            initialReasonCode: initialReasonCode,
            initialReasonText: initialReasonText,
            initialMessage: initialMessage,
            initialShiftId: _isHelper ? _selectedHelperShiftId : '',
            isFixingPreviousPending: isFixingPreviousPending,
            previousSessionId: previousSessionId,
            previousWorkDate: previousWorkDate,
            previousShiftId: previousShiftId,
          ),
        ),
      );

      return ok == true;
    } finally {
      _openingManualRequestFlow = false;
    }
  }

  Future<void> _showManualAttendanceRequiredDialog({
    required String title,
    required String message,
    required String manualRequestType,
    String initialReasonCode = '',
    String initialReasonText = '',
  }) async {
    if (!mounted) return;

    final openManual = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ปิด'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('ส่งคำขอแก้ไขเวลา'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!openManual) return;

    final submitted = await _openManualAttendanceRequest(
      manualRequestType: manualRequestType,
      initialReasonCode: initialReasonCode,
      initialReasonText: initialReasonText,
      initialMessage: message,
    );

    if (submitted) {
      _snack('ส่งคำขอแก้ไขเวลาเรียบร้อยแล้ว');
      await _refreshAttendanceToday(silent: true);
    }
  }

  Future<void> _showPreviousAttendancePendingDialog({
    required String title,
    required String message,
    required String previousSessionId,
    required String previousWorkDate,
    required String previousShiftId,
    String previousClinicName = '',
  }) async {
    if (!mounted) return;

    final openManual = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ปิด'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('แก้รายการวันก่อน'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!openManual) return;

    final submitted = await _openManualAttendanceRequest(
      manualRequestType: 'forgot_checkout',
      initialReasonCode: 'PREVIOUS_OPEN_SESSION',
      initialReasonText: '',
      initialMessage: message,
      isFixingPreviousPending: true,
      previousSessionId: previousSessionId,
      previousWorkDate: previousWorkDate,
      previousShiftId: previousShiftId,
      previousClinicName: previousClinicName,
    );

    if (submitted) {
      _snack('ส่งคำขอแก้ไขรายการค้างของวันก่อนเรียบร้อยแล้ว');
      await _refreshAttendanceToday(silent: true);
    }
  }

  Future<Map<String, String>?> _showEarlyCheckoutReasonDialog() async {
    if (!mounted) return null;

    String selectedReasonCode = 'EARLY_CHECKOUT';
    final reasonTextCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String err = '';
    bool submitting = false;

    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            void closeWithResult(Map<String, String> value) {
              FocusScope.of(ctx).unfocus();
              setSt(() {
                submitting = true;
                err = '';
              });

              Future<void>.delayed(Duration.zero, () {
                if (!ctx.mounted) return;
                Navigator.of(ctx, rootNavigator: true).pop(value);
              });
            }

            return AlertDialog(
              title: const Text('เช็คเอาท์ก่อนเวลา'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'กรุณาระบุเหตุผลก่อนเช็คเอาท์',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedReasonCode,
                      decoration: const InputDecoration(
                        labelText: 'เหตุผล',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'EARLY_CHECKOUT',
                          child: Text('เช็คเอาท์ก่อนเวลา'),
                        ),
                        DropdownMenuItem(
                          value: 'PERSONAL_REASON',
                          child: Text('ติดธุระส่วนตัว'),
                        ),
                        DropdownMenuItem(
                          value: 'SICK',
                          child: Text('ไม่สบาย'),
                        ),
                        DropdownMenuItem(
                          value: 'EMERGENCY',
                          child: Text('เหตุฉุกเฉิน'),
                        ),
                        DropdownMenuItem(
                          value: 'OTHER',
                          child: Text('อื่น ๆ'),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (v) {
                              if (v == null) return;
                              setSt(() {
                                selectedReasonCode = v;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonTextCtrl,
                      enabled: !submitting,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียดเหตุผล',
                        hintText: 'เช่น มีเหตุจำเป็นต้องกลับก่อนเวลา',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      enabled: !submitting,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุเพิ่มเติม',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (err.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          err,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () {
                          FocusScope.of(ctx).unfocus();
                          Navigator.of(ctx, rootNavigator: true).pop(null);
                        },
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () {
                          final reasonText = reasonTextCtrl.text.trim();
                          final note = noteCtrl.text.trim();

                          if (reasonText.isEmpty && note.isEmpty) {
                            setSt(() {
                              err = 'กรุณาระบุรายละเอียดอย่างน้อย 1 ช่อง';
                            });
                            return;
                          }

                          closeWithResult({
                            'reasonCode': selectedReasonCode,
                            'reasonText': reasonText,
                            'note': note,
                          });
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      reasonTextCtrl.dispose();
      noteCtrl.dispose();
    });

    return result;
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
    String okText = 'ตกลง',
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(okText),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showHelperShiftResolutionDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    final openPicker = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ปิด'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('เลือกกะงาน'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!openPicker) return;

    await _showHelperShiftPicker();
  }

  String _stringFromMap(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _clinicSessionLabel(Map<String, dynamic> body) {
    final clinicName = _stringFromMap(body, [
      'existingClinicName',
      'clinicName',
      'existingClinicLabel',
      'clinicLabel',
    ]);
    final clinicId = _stringFromMap(body, ['existingClinicId', 'clinicId']);
    final workDate = _stringFromMap(body, ['existingWorkDate', 'workDate']);
    final shiftName = _stringFromMap(body, [
      'existingShiftName',
      'shiftName',
      'existingShiftLabel',
      'shiftLabel',
    ]);
    final shiftId = _stringFromMap(body, ['existingShiftId', 'shiftId']);

    final clinicLabel = clinicName.isNotEmpty ? clinicName : clinicId;
    final finalShiftLabel = shiftName.isNotEmpty ? shiftName : shiftId;

    final pieces = <String>[];
    if (clinicLabel.isNotEmpty) pieces.add('คลินิก $clinicLabel');
    if (workDate.isNotEmpty) pieces.add('วันที่ $workDate');
    if (finalShiftLabel.isNotEmpty) pieces.add('กะ $finalShiftLabel');
    return pieces.join(' • ');
  }

  String _previousPendingSessionLabel() {
    final clinicLabel = _attPreviousClinicName.trim().isNotEmpty
        ? _attPreviousClinicName.trim()
        : _attPreviousClinicId.trim();

    final pieces = <String>[];
    if (clinicLabel.isNotEmpty) {
      pieces.add('คลินิก $clinicLabel');
    }
    if (_attPreviousWorkDate.trim().isNotEmpty) {
      pieces.add('วันที่ ${_attPreviousWorkDate.trim()}');
    }
    if (_attPreviousShiftId.trim().isNotEmpty) {
      pieces.add('กะ ${_attPreviousShiftId.trim()}');
    }
    return pieces.join(' • ');
  }

  String _manualRequestTypeTitle(String type) {
    switch (type) {
      case 'check_in':
        return 'ขอเช็คอินย้อนหลัง';
      case 'check_out':
        return 'ขอเช็คเอาท์ย้อนหลัง';
      case 'forgot_checkout':
        return 'ลืมเช็คเอาท์';
      case 'edit_both':
      default:
        return 'ขอแก้ไขเวลาเข้า-ออก';
    }
  }

  String _manualRequestTypeSubtitle(String type) {
    switch (type) {
      case 'check_in':
        return 'ใช้เมื่อยังไม่มีรายการลงเวลา และต้องการขอเวลาเข้างาน';
      case 'check_out':
        return 'ใช้เมื่อมีเช็คอินอยู่แล้ว แต่ต้องการขอเวลาออกงาน';
      case 'forgot_checkout':
        return 'ใช้เมื่อเช็คอินแล้ว แต่ลืมเช็คเอาท์';
      case 'edit_both':
      default:
        return 'ใช้เมื่อจำเป็นต้องขอแก้ทั้งเวลาเข้าและเวลาออก';
    }
  }

  IconData _manualRequestTypeIcon(String type) {
    switch (type) {
      case 'check_in':
        return Icons.login;
      case 'check_out':
        return Icons.logout;
      case 'forgot_checkout':
        return Icons.history_toggle_off;
      case 'edit_both':
      default:
        return Icons.edit_calendar_outlined;
    }
  }

  Future<void> _openManualRequestByType(
    String manualRequestType, {
    String initialReasonCode = '',
    String initialReasonText = '',
    String initialMessage = '',
  }) async {
    if (!_canOpenManualRequest()) return;

    final submitted = await _openManualAttendanceRequest(
      manualRequestType: manualRequestType,
      initialReasonCode: initialReasonCode,
      initialReasonText: initialReasonText,
      initialMessage: initialMessage,
    );

    if (submitted) {
      _snack('ส่งคำขอเรียบร้อยแล้ว');
      await _refreshAttendanceToday(silent: true);
    }
  }

  Future<void> _openPreviousPendingManualFix() async {
    if (!_hasPreviousPendingBlock) {
      _snack('ไม่พบรายการวันก่อนที่ต้องแก้ไข');
      return;
    }

    if (!_canOpenManualRequest(helperShiftRequired: false)) return;

    final message = _attPreviousPendingMessage.trim().isNotEmpty
        ? _attPreviousPendingMessage.trim()
        : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรอการอนุมัติก่อน';

    final submitted = await _openManualAttendanceRequest(
      manualRequestType: 'forgot_checkout',
      initialReasonCode: 'PREVIOUS_OPEN_SESSION',
      initialReasonText: '',
      initialMessage: message,
      isFixingPreviousPending: true,
      previousSessionId: _attPreviousSessionId,
      previousWorkDate: _attPreviousWorkDate,
      previousShiftId: _attPreviousShiftId,
      previousClinicName: _attPreviousClinicName,
    );

    if (submitted) {
      _snack('ส่งคำขอแก้ไขรายการค้างของวันก่อนเรียบร้อยแล้ว');
      await _refreshAttendanceToday(silent: true);
    }
  }

  Future<void> _showManualRequestMenu() async {
    if (!_canOpenManualRequest()) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final types = <String>[
          'check_in',
          'check_out',
          'forgot_checkout',
          'edit_both',
        ];

        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: types.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return ListTile(
                  title: const Text(
                    'เลือกประเภทคำขอแก้ไขเวลา',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    _isHelper
                        ? (_selectedHelperShift == null
                            ? 'กรุณาเลือกกะก่อนส่งคำขอ'
                            : 'กะที่เลือก: $_selectedHelperShiftLabel')
                        : 'เลือกประเภทคำขอที่ต้องการส่งให้คลินิกอนุมัติ',
                  ),
                );
              }

              final type = types[i - 1];
              return ListTile(
                leading: Icon(_manualRequestTypeIcon(type)),
                title: Text(_manualRequestTypeTitle(type)),
                subtitle: Text(_manualRequestTypeSubtitle(type)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, type),
              );
            },
          ),
        );
      },
    );

    if (picked == null || picked.isEmpty) return;
    await _openManualRequestByType(picked);
  }

  Future<_AttendanceSubmitResult> _handleAttendanceConflictResponse(
    http.Response res, {
    required bool isCheckIn,
  }) async {
    final code = _extractApiCode(res);
    final apiMsg = _extractApiMessage(res);
    final body = _decodeBodyMap(res.body);

    if (code == 'PREVIOUS_ATTENDANCE_PENDING') {
      _applyPreviousPendingBlockFromMap(body);

      final message = apiMsg.isNotEmpty
          ? apiMsg
          : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน';

      await _showPreviousAttendancePendingDialog(
        title: 'ยังมีรายการวันก่อนค้างอยู่',
        message: message,
        previousSessionId: _attPreviousSessionId,
        previousWorkDate: _attPreviousWorkDate,
        previousShiftId: _attPreviousShiftId,
        previousClinicName: _attPreviousClinicName,
      );

      return _AttendanceSubmitResult.previousAttendancePending;
    }

    if (code == 'ALREADY_CHECKED_IN') {
      _snack('วันนี้คุณเช็คอินแล้ว');
      return _AttendanceSubmitResult.alreadyDone;
    }

    if (code == 'ATTENDANCE_ALREADY_COMPLETED') {
      _snack(
        _isHelper && _selectedHelperShiftId.isNotEmpty
            ? 'กะนี้บันทึกเวลาเข้า-ออกครบแล้ว'
            : 'วันนี้คุณบันทึกเวลาเข้า-ออกครบแล้ว',
      );
      return _AttendanceSubmitResult.alreadyDone;
    }

    if (code == 'NO_OPEN_SESSION') {
      _snack(
        _isHelper && _selectedHelperShiftId.isNotEmpty
            ? 'ไม่พบรายการเช็คอินที่เปิดอยู่สำหรับกะนี้'
            : 'ไม่พบรายการเช็คอินที่เปิดอยู่สำหรับวันนี้',
      );
      return _AttendanceSubmitResult.failed;
    }

    if (code == 'CHECKOUT_TOO_FAST') {
      final msg = apiMsg.isNotEmpty
          ? apiMsg
          : 'ยังไม่สามารถเช็คเอาท์ได้ในขณะนี้ กรุณารอสักครู่แล้วลองใหม่';
      _snack(msg);
      return _AttendanceSubmitResult.failed;
    }

    if (code == 'MANUAL_REQUIRED_PREVIOUS_OPEN_SESSION') {
      await _showManualAttendanceRequiredDialog(
        title: 'จำเป็นต้องใช้การแก้ไขเวลา',
        message:
            'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ จึงไม่สามารถเช็คอินใหม่ได้\n\nกรุณาส่งคำขอแก้ไขเวลาเพื่อให้คลินิกตรวจสอบและอนุมัติ',
        manualRequestType: 'edit_both',
        initialReasonCode: 'PREVIOUS_OPEN_SESSION',
      );
      return _AttendanceSubmitResult.manualRequired;
    }

    if (code == 'MANUAL_REQUIRED_EARLY_CHECKIN') {
      await _showManualAttendanceRequiredDialog(
        title: 'เช็คอินก่อนเวลางาน',
        message:
            'การเช็คอินก่อนเวลางานต้องส่งคำขอแก้ไขเวลา พร้อมระบุเหตุผล และรอคลินิกอนุมัติ',
        manualRequestType: 'check_in',
        initialReasonCode: 'EARLY_CHECKIN',
      );
      return _AttendanceSubmitResult.manualRequired;
    }

    if (code == 'MANUAL_REQUIRED_AFTER_CUTOFF') {
      await _showManualAttendanceRequiredDialog(
        title: 'เกินเวลาที่กำหนด',
        message:
            'เลยเวลาที่กำหนดของวันนั้นแล้ว จึงไม่สามารถสแกนเช็คเอาท์ได้\n\nกรุณาส่งคำขอแก้ไขเวลาและรอคลินิกอนุมัติ',
        manualRequestType: 'forgot_checkout',
        initialReasonCode: 'FORGOT_CHECKOUT',
      );
      return _AttendanceSubmitResult.manualRequired;
    }

    if (code == 'EARLY_CHECKOUT_REASON_REQUIRED') {
      return _AttendanceSubmitResult.earlyCheckoutReasonRequired;
    }

    if (code == 'MULTIPLE_ACTIVE_SHIFTS') {
      await _showHelperShiftResolutionDialog(
        title: 'พบหลายกะงานในช่วงเวลาเดียวกัน',
        message: apiMsg.isNotEmpty
            ? apiMsg
            : 'วันนี้มีหลายกะงานที่เวลาซ้อนกัน ระบบยังไม่สามารถรู้ได้ว่าท่านกำลังสแกนให้คลินิกไหน\n\nกรุณาเลือกกะงานที่กำลังทำอยู่ก่อน แล้วค่อยสแกนใหม่',
      );
      return _AttendanceSubmitResult.shiftSelectionRequired;
    }

    if (code == 'SHIFT_NOT_RESOLVED') {
      await _showHelperShiftResolutionDialog(
        title: 'ยังไม่สามารถระบุกะงานได้',
        message: apiMsg.isNotEmpty
            ? apiMsg
            : 'ระบบยังไม่สามารถระบุได้ว่าตอนนี้ท่านกำลังทำงานให้คลินิกไหน\n\nกรุณาเลือกกะงานของวันนี้ก่อน แล้วค่อยสแกนใหม่',
      );
      return _AttendanceSubmitResult.shiftSelectionRequired;
    }

    if (code == 'NO_SHIFT_TODAY') {
      await _showInfoDialog(
        title: 'ไม่พบกะงานของวันนี้',
        message: apiMsg.isNotEmpty
            ? apiMsg
            : 'วันนี้ยังไม่พบกะงานที่สามารถใช้สแกนได้ กรุณาตรวจสอบตารางงานอีกครั้ง',
      );
      return _AttendanceSubmitResult.shiftSelectionRequired;
    }

    if (code == 'SHIFT_NOT_FOUND') {
      await _showInfoDialog(
        title: 'ไม่พบกะงานที่เลือก',
        message: apiMsg.isNotEmpty
            ? apiMsg
            : 'ไม่พบกะงานที่เลือกในระบบ กรุณาเลือกกะใหม่อีกครั้ง',
      );
      await _loadHelperTodayShifts(silent: true);
      return _AttendanceSubmitResult.shiftSelectionRequired;
    }

    if (code == 'SHIFT_NOT_ASSIGNED_TO_HELPER') {
      await _showInfoDialog(
        title: 'กะงานนี้ไม่ได้เป็นของบัญชีนี้',
        message: apiMsg.isNotEmpty
            ? apiMsg
            : 'กะงานที่เลือกไม่ได้ถูกมอบหมายให้บัญชีนี้ กรุณาเลือกกะใหม่',
      );
      await _loadHelperTodayShifts(silent: true);
      return _AttendanceSubmitResult.shiftSelectionRequired;
    }

    if (code == 'SHIFT_DATE_MISMATCH') {
      await _showInfoDialog(
        title: 'วันที่ของกะไม่ตรงกัน',
        message: apiMsg.isNotEmpty
            ? apiMsg
            : 'กะงานที่เลือกไม่ตรงกับวันที่วันนี้ กรุณาเลือกกะใหม่',
      );
      await _loadHelperTodayShifts(silent: true);
      return _AttendanceSubmitResult.shiftSelectionRequired;
    }

    if (code == 'ALREADY_CHECKED_IN_OTHER_SESSION') {
      final label = _clinicSessionLabel(body);
      await _showInfoDialog(
        title: 'มีการเช็คอินค้างอยู่แล้ว',
        message: label.isNotEmpty
            ? 'ตอนนี้ท่านมี session ที่ยังไม่ปิดอยู่แล้ว\n$label\n\nกรุณาเช็คเอาท์ session เดิมให้เรียบร้อยก่อน จึงจะเช็คอินคลินิกใหม่ได้'
            : 'ตอนนี้ท่านมี session ที่ยังไม่ปิดอยู่แล้ว\n\nกรุณาเช็คเอาท์ session เดิมให้เรียบร้อยก่อน จึงจะเช็คอินคลินิกใหม่ได้',
      );
      return _AttendanceSubmitResult.checkedInOtherClinic;
    }

    if (code == 'MULTIPLE_OPEN_SESSIONS') {
      await _showInfoDialog(
        title: 'พบรายการลงเวลาที่เปิดอยู่หลายรายการ',
        message: apiMsg.isNotEmpty
            ? apiMsg
            : 'ระบบพบ open session มากกว่าหนึ่งรายการ จึงไม่สามารถเดาเองได้ว่าควรปิดรายการใด\n\nกรุณาให้ผู้ดูแลตรวจสอบข้อมูล หรือใช้ flow แก้ไขเวลาให้ถูกต้องก่อน',
      );
      return _AttendanceSubmitResult.multipleOpenSessions;
    }

    if (code == 'MANUAL_REQUEST_PENDING') {
      final msg = apiMsg.isNotEmpty
          ? apiMsg
          : 'มีคำขอแก้ไขเวลาค้างอนุมัติอยู่แล้วสำหรับวันนี้';
      _snack(msg);
      return _AttendanceSubmitResult.manualRequired;
    }

    if (code == 'LOCATION_REQUIRED') {
      final msg = _locationMessageFromApi(
        fallback: 'กรุณาเปิด GPS และอนุญาตตำแหน่งก่อนบันทึกเวลาทำงาน',
        response: res,
      );
      _setAttendanceLocationState(error: msg);
      _snack(msg);
      return _AttendanceSubmitResult.locationUnavailable;
    }

    if (code == 'OUTSIDE_ALLOWED_RADIUS') {
      final msg = _locationMessageFromApi(
        fallback: 'คุณอยู่นอกพื้นที่คลินิกที่กำหนด ไม่สามารถบันทึกเวลาได้',
        response: res,
      );
      _setAttendanceLocationState(error: msg);
      _snack(msg);
      return _AttendanceSubmitResult.locationUnavailable;
    }

    if (code == 'CLINIC_LOCATION_NOT_SET') {
      final msg = _locationMessageFromApi(
        fallback: 'ยังไม่ได้ตั้งพิกัดอ้างอิงของคลินิก กรุณาตั้งค่าก่อนใช้งาน',
        response: res,
      );
      _setAttendanceLocationState(error: msg);
      _snack(msg);
      return _AttendanceSubmitResult.locationUnavailable;
    }

    if (apiMsg.isNotEmpty) {
      _snack(apiMsg);
    } else {
      _snack(
        isCheckIn
            ? 'ไม่สามารถบันทึกเวลาเข้างานได้ กรุณาลองใหม่'
            : 'ไม่สามารถบันทึกเวลาออกงานได้ กรุณาลองใหม่',
      );
    }
    return _AttendanceSubmitResult.failed;
  }

  void _applyImmediateCheckInUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      _attCheckedOut = false;
      _attBlockedByPreviousPending = false;
      _attPreviousPendingMessage = '';
      _attPreviousSessionId = '';
      _attPreviousWorkDate = '';
      _attPreviousShiftId = '';
      _attPreviousClinicId = '';
      _attPreviousClinicName = '';
      _attPreviousAction = '';
      _attPreviousSession = <String, dynamic>{};
      _attStatusLine = _isHelper && _selectedHelperShift != null
          ? 'เช็คอินกะที่เลือกเรียบร้อยแล้ว (ยังไม่ได้เช็คเอาท์)'
          : 'วันนี้เช็คอินเรียบร้อยแล้ว (ยังไม่ได้เช็คเอาท์)';
    });
  }

  void _applyImmediateCheckOutUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      _attCheckedOut = true;
      _attBlockedByPreviousPending = false;
      _attPreviousPendingMessage = '';
      _attPreviousSessionId = '';
      _attPreviousWorkDate = '';
      _attPreviousShiftId = '';
      _attPreviousClinicId = '';
      _attPreviousClinicName = '';
      _attPreviousAction = '';
      _attPreviousSession = <String, dynamic>{};
      _attStatusLine = _isHelper && _selectedHelperShift != null
          ? 'เช็คอินและเช็คเอาท์กะที่เลือกเรียบร้อยแล้ว'
          : 'วันนี้เช็คอินและเช็คเอาท์เรียบร้อยแล้ว';
    });
  }

  void _applyImmediateAlreadyCheckedInUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      _attCheckedOut = false;
      _attStatusLine = _isHelper && _selectedHelperShift != null
          ? 'กะนี้เช็คอินเรียบร้อยแล้ว (ยังไม่ได้เช็คเอาท์)'
          : 'วันนี้เช็คอินเรียบร้อยแล้ว (ยังไม่ได้เช็คเอาท์)';
    });
  }

  void _applyImmediateAlreadyCheckedOutUi() {
    if (!mounted) return;
    setState(() {
      _attErr = '';
      _attCheckedIn = true;
      _attCheckedOut = true;
      _attStatusLine = _isHelper && _selectedHelperShift != null
          ? 'กะนี้เช็คอินและเช็คเอาท์เรียบร้อยแล้ว'
          : 'วันนี้เช็คอินและเช็คเอาท์เรียบร้อยแล้ว';
    });
  }

  Future<void> _refreshAttendanceToday({bool silent = false}) async {
    if (_ctxLoading) return;
    if (!_isAttendanceUser) return;
    if (!_attendancePremiumEnabled) return;
    if (_attBusy && !silent) {
      print('[ATTENDANCE][REFRESH] skipped because busy');
      return;
    }

    if (_isHelper &&
        !_helperShiftLoading &&
        _helperTodayShifts.isEmpty &&
        !_helperShiftTouchedByUser) {
      await _loadHelperTodayShifts(silent: true);
    }

    final int seq = ++_attRefreshSeq;

    if (!silent && mounted) {
      setState(() {
        _attLoading = true;
        _attErr = '';
      });
    }

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) throw Exception('no token');

      final workDate = _todayYmd();

      try {
        final preview = await AttendanceApi.myDayPreview(
          token: token,
          workDate: workDate,
          shiftId: _isHelper ? _selectedHelperShiftId : null,
        );

        if (seq != _attRefreshSeq) return;

        final dataAny = (preview['data'] is Map) ? preview['data'] : preview;
        final data = (dataAny is Map)
            ? Map<String, dynamic>.from(dataAny)
            : <String, dynamic>{};

        _clearPreviousPendingBlock();

        if (data['policy'] is Map) {
          _applyPolicyFromMap(Map<String, dynamic>.from(data['policy']));
        }

        if (_isHelper) {
          final runtime = (data['runtime'] is Map)
              ? Map<String, dynamic>.from(data['runtime'])
              : <String, dynamic>{};

          final availableAny = runtime['availableShifts'];
          if (availableAny is List) {
            final shifts = availableAny
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            final deduped = _sortHelperShifts(_dedupeHelperShiftList(shifts));

            if (mounted && deduped.isNotEmpty) {
              setState(() {
                _helperTodayShifts = deduped;
              });
            }
          }

          if (runtime['shift'] is Map) {
            final runtimeShift = Map<String, dynamic>.from(runtime['shift']);
            final mode =
                (runtime['shiftSelectionMode'] ?? '').toString().trim();

            if (_selectedHelperShift == null ||
                !_helperShiftTouchedByUser ||
                _sameShiftIdentity(runtimeShift, _selectedHelperShift)) {
              _applySelectedHelperShift(
                runtimeShift,
                runtimeSelectionMode: mode,
              );
            }
          }
        }

        final attendance =
            _mapFromAny(data['attendance']) ?? <String, dynamic>{};
        final pendingManualAny = attendance['pendingManualSession'];
        final hasPendingManual = pendingManualAny is Map &&
            Map<String, dynamic>.from(pendingManualAny).isNotEmpty;

        List<Map<String, dynamic>> sessions = <Map<String, dynamic>>[];
        if (data['sessions'] is List) {
          sessions = (data['sessions'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (attendance['sessions'] is List) {
          sessions = (attendance['sessions'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        if (_isHelper && _selectedHelperShiftId.isNotEmpty) {
          sessions = sessions.where(_sessionMatchesSelectedHelperShift).toList();
        }

        Map<String, dynamic>? todayOpen;
        Map<String, dynamic>? todayDone;

        for (final s in sessions) {
          if (!_isTodaySession(s)) continue;

          if (_sessionLooksOpen(s)) {
            todayOpen = s;
            break;
          }

          if (_sessionLooksClosed(s)) {
            todayDone ??= s;
          }
        }

        final previewHasCheckIn = _previewHasCheckInEvidence(data);
        final previewHasCheckOut = _previewHasCheckOutEvidence(data);

        final checkedIn =
            previewHasCheckIn || todayOpen != null || todayDone != null;
        final checkedOut = previewHasCheckOut || todayDone != null;

        final msg = (data['message'] ?? '').toString().trim();
        final line = _buildAttendanceStatusLine(
          checkedIn: checkedIn,
          checkedOut: checkedOut,
          hasPendingManual: hasPendingManual,
          message: msg,
        );

        print(
          '[ATTENDANCE][REFRESH][PREVIEW] '
          'previewHasCheckIn=$previewHasCheckIn '
          'previewHasCheckOut=$previewHasCheckOut '
          'todayOpen=${todayOpen != null} '
          'todayDone=${todayDone != null} '
          'hasPendingManual=$hasPendingManual '
          '=> checkedIn=$checkedIn checkedOut=$checkedOut',
        );

        if (!mounted || seq != _attRefreshSeq) return;
        setState(() {
          _attLoading = false;
          _attErr = '';
          _attStatusLine = line;
          _attCheckedIn = checkedIn;
          _attCheckedOut = checkedOut;
        });
        return;
      } on AttendanceApiException catch (e) {
        print('[ATTENDANCE][REFRESH][PREVIEW][API] $e');

        if (e.isPreviousAttendancePending) {
          if (seq != _attRefreshSeq) return;

          _applyPreviousPendingBlockFromMap(e.data);

          String line = e.message.trim().isNotEmpty
              ? e.message.trim()
              : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน';

          if (_isHelper && _selectedHelperShift != null) {
            line = '$line\nกะที่เลือก: $_selectedHelperShiftLabel';
          }

          if (!mounted || seq != _attRefreshSeq) return;
          setState(() {
            _attLoading = false;
            _attErr = '';
            _attStatusLine = line;
            _attCheckedIn = false;
            _attCheckedOut = false;
          });
          return;
        }
      } catch (e) {
        print('[ATTENDANCE][REFRESH][PREVIEW] $e');
      }

      final me = await AttendanceApi.mySessions(
        token: token,
        dateFrom: workDate,
        dateTo: workDate,
        shiftId: _isHelper ? _selectedHelperShiftId : null,
      );

      if (seq != _attRefreshSeq) return;

      _clearPreviousPendingBlock();

      final list = _extractAttendanceList(me);

      Map<String, dynamic>? todayOpen;
      Map<String, dynamic>? todayDone;

      for (final s in list) {
        if (!_isTodaySession(s)) continue;

        if (_sessionLooksOpen(s)) {
          todayOpen = s;
          break;
        }

        if (_sessionLooksClosed(s)) {
          todayDone ??= s;
        }
      }

      final checkedIn = todayOpen != null || todayDone != null;
      final checkedOut = todayDone != null;

      final line = _buildAttendanceStatusLine(
        checkedIn: checkedIn,
        checkedOut: checkedOut,
        hasPendingManual: false,
        message: '',
      );

      if (!mounted || seq != _attRefreshSeq) return;
      setState(() {
        _attLoading = false;
        _attErr = '';
        _attStatusLine = line;
        _attCheckedIn = checkedIn;
        _attCheckedOut = checkedOut;
      });
    } catch (e) {
      if (!mounted || seq != _attRefreshSeq) return;
      setState(() {
        _attLoading = false;
        _attErr = _friendlyAuthError(e);
      });
    }
  }

  Future<_AttendanceSubmitResult> _postAttendanceCheckIn({
    required String token,
    Position? position,
  }) async {
    try {
      await AttendanceApi.checkIn(
        token: token,
        workDate: _todayYmd(),
        shiftId: _isHelper ? _selectedHelperShiftId : null,
        biometricVerified: true,
        lat: position?.latitude ?? _attLat,
        lng: position?.longitude ?? _attLng,
      );

      print('[ATTENDANCE][CHECKIN][API] success');
      return _AttendanceSubmitResult.success;
    } on AttendanceApiException catch (e) {
      print('[ATTENDANCE][CHECKIN][API] $e');

      if (e.isPreviousAttendancePending) {
        _applyPreviousPendingBlockFromMap(e.data);

        final message = e.message.trim().isNotEmpty
            ? e.message.trim()
            : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน';

        final previousClinicName =
            (e.data['previousClinicName'] ?? '').toString().trim();

        await _showPreviousAttendancePendingDialog(
          title: 'ยังมีรายการวันก่อนค้างอยู่',
          message: message,
          previousSessionId: e.previousSessionId,
          previousWorkDate: e.previousWorkDate,
          previousShiftId: e.previousShiftId,
          previousClinicName: previousClinicName,
        );

        return _AttendanceSubmitResult.previousAttendancePending;
      }

      if (e.statusCode == 401) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
        return _AttendanceSubmitResult.unauthorized;
      }

      if (e.statusCode == 403) {
        _snack(
          e.message.isNotEmpty ? e.message : 'คุณไม่มีสิทธิ์บันทึกเวลาเข้างาน',
        );
        return _AttendanceSubmitResult.forbidden;
      }

      if (e.statusCode == 400 || e.statusCode == 409) {
        final fakeRes = http.Response(
          jsonEncode(e.data),
          e.statusCode,
          headers: const {'content-type': 'application/json'},
        );
        return await _handleAttendanceConflictResponse(
          fakeRes,
          isCheckIn: true,
        );
      }

      _snack(
        e.message.isNotEmpty
            ? e.message
            : 'ไม่สามารถบันทึกเวลาเข้างานได้ กรุณาลองใหม่',
      );
      return _AttendanceSubmitResult.failed;
    } catch (e) {
      final text = e.toString();
      print('[ATTENDANCE][CHECKIN] ERROR $text');

      if (text.startsWith('Exception: ')) {
        _snack(text.replaceFirst('Exception: ', ''));
      } else {
        _snack('ไม่สามารถบันทึกเวลาเข้างานได้ กรุณาลองใหม่');
      }

      return _AttendanceSubmitResult.failed;
    }
  }

  Future<_AttendanceSubmitResult> _postAttendanceCheckOut({
    required String token,
    String? reasonCode,
    String? reasonText,
    String? note,
    Position? position,
  }) async {
    try {
      await AttendanceApi.checkOut(
        token: token,
        workDate: _todayYmd(),
        shiftId: _isHelper ? _selectedHelperShiftId : null,
        biometricVerified: true,
        reasonCode: reasonCode ?? '',
        reasonText: reasonText ?? '',
        note: note ?? '',
        lat: position?.latitude ?? _attLat,
        lng: position?.longitude ?? _attLng,
      );

      print('[ATTENDANCE][CHECKOUT][API] success');
      return _AttendanceSubmitResult.success;
    } on AttendanceApiException catch (e) {
      print('[ATTENDANCE][CHECKOUT][API] $e');

      if (e.isPreviousAttendancePending) {
        _applyPreviousPendingBlockFromMap(e.data);

        final message = e.message.trim().isNotEmpty
            ? e.message.trim()
            : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน';

        final previousClinicName =
            (e.data['previousClinicName'] ?? '').toString().trim();

        await _showPreviousAttendancePendingDialog(
          title: 'ยังมีรายการวันก่อนค้างอยู่',
          message: message,
          previousSessionId: e.previousSessionId,
          previousWorkDate: e.previousWorkDate,
          previousShiftId: e.previousShiftId,
          previousClinicName: previousClinicName,
        );

        return _AttendanceSubmitResult.previousAttendancePending;
      }

      if (e.statusCode == 401) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
        return _AttendanceSubmitResult.unauthorized;
      }

      if (e.statusCode == 403) {
        _snack(
          e.message.isNotEmpty ? e.message : 'คุณไม่มีสิทธิ์บันทึกเวลาออกงาน',
        );
        return _AttendanceSubmitResult.forbidden;
      }

      if (e.statusCode == 400 || e.statusCode == 409) {
        final fakeRes = http.Response(
          jsonEncode(e.data),
          e.statusCode,
          headers: const {'content-type': 'application/json'},
        );
        return await _handleAttendanceConflictResponse(
          fakeRes,
          isCheckIn: false,
        );
      }

      _snack(
        e.message.isNotEmpty
            ? e.message
            : 'ไม่สามารถบันทึกเวลาออกงานได้ กรุณาลองใหม่',
      );
      return _AttendanceSubmitResult.failed;
    } catch (e) {
      final text = e.toString();
      print('[ATTENDANCE][CHECKOUT] ERROR $text');

      if (text.startsWith('Exception: ')) {
        _snack(text.replaceFirst('Exception: ', ''));
      } else {
        _snack('ไม่สามารถบันทึกเวลาออกงานได้ กรุณาลองใหม่');
      }

      return _AttendanceSubmitResult.failed;
    }
  }

  Future<void> _scanAndCheckIn() async {
    _tapLog('SCAN_CHECKIN');
    print('[ATTENDANCE] ROLE=$_role clinicId=$_clinicId staffId=$_staffId');

    if (_attActionLock || _attBusy) {
      _snack('กรุณารอสักครู่ ระบบกำลังดำเนินการ');
      print('[ATTENDANCE][CHECKIN] BLOCKED busy/actionLock');
      return;
    }
    _attActionLock = true;

    try {
      if (_ctxLoading) {
        print('[ATTENDANCE][CHECKIN] BLOCKED ctxLoading=$_ctxLoading');
        _snack('กำลังเตรียมข้อมูล กรุณาลองอีกครั้ง');
        return;
      }

      if (!_isAttendanceUser) {
        _snack('เมนูนี้สำหรับพนักงานหรือผู้ช่วยเท่านั้น');
        return;
      }

      if (!_attendancePremiumEnabled) {
        _snack('ฟีเจอร์นี้สำหรับแพ็กเกจพรีเมียม');
        return;
      }

      if (_hasPreviousPendingBlock) {
        final label = _previousPendingSessionLabel();
        await _showPreviousAttendancePendingDialog(
          title: 'ยังมีรายการวันก่อนค้างอยู่',
          message: label.isNotEmpty
              ? 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่\n$label\n\nกรุณาแก้ไขและรออนุมัติก่อน จึงจะเริ่มลงเวลาวันใหม่ได้'
              : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน จึงจะเริ่มลงเวลาวันใหม่ได้',
          previousSessionId: _attPreviousSessionId,
          previousWorkDate: _attPreviousWorkDate,
          previousShiftId: _attPreviousShiftId,
          previousClinicName: _attPreviousClinicName,
        );
        return;
      }

      if (_isHelper && !_helperCanProceedScan()) {
        return;
      }

      if (_attCheckedIn && !_attCheckedOut) {
        _snack(
          _isHelper && _selectedHelperShiftId.isNotEmpty
              ? 'กะนี้เช็คอินแล้ว'
              : 'วันนี้คุณเช็คอินแล้ว',
        );
        return;
      }

      if (_attCheckedIn && _attCheckedOut) {
        _snack(
          _isHelper && _selectedHelperShiftId.isNotEmpty
              ? 'กะนี้บันทึกเวลาเข้า-ออกครบแล้ว'
              : 'วันนี้คุณบันทึกเวลาเข้า-ออกครบแล้ว',
        );
        return;
      }

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingInBio,
        progressText: _isHelper
            ? (_selectedHelperShift == null
                ? 'กรุณาเลือกกะก่อน แล้วสแกนลายนิ้วมือ'
                : 'กำลังสแกนสำหรับกะ: $_selectedHelperShiftLabel')
            : 'กรุณาสแกนลายนิ้วมือ',
        clearErr: true,
      );

      print('[ATTENDANCE][CHECKIN] BEFORE BIO');
      final okBio = await _biometricAuthenticate();
      print('[ATTENDANCE][CHECKIN] AFTER BIO ok=$okBio');

      if (!okBio) return;

      Position? position;
      if (_attendanceNeedsLiveLocation) {
        _setAttendanceUiPhase(
          _AttendanceUiPhase.checkingInSubmit,
          progressText: 'กำลังตรวจสอบตำแหน่งปัจจุบัน',
          clearErr: true,
        );

        position = await _readAttendancePosition();
        if (position == null) {
          return;
        }
      }

      final token = await _getTokenAny();
      print(
        '[ATTENDANCE][CHECKIN] TOKEN exists=${token != null && token.isNotEmpty}',
      );

      if (token == null || token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
        return;
      }

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingInSubmit,
        progressText: _isHelper
            ? 'กำลังตรวจสอบกะงานและบันทึกเวลา'
            : (_attendanceNeedsLiveLocation
                ? 'กำลังตรวจสอบตำแหน่งและบันทึกเวลา'
                : 'กำลังบันทึกข้อมูล'),
      );
      _startSlowNetworkHint();

      print('[ATTENDANCE][CHECKIN] BEFORE POST');
      final result = await _postAttendanceCheckIn(
        token: token,
        position: position,
      );
      print('[ATTENDANCE][CHECKIN] RESULT=$result');

      if (result == _AttendanceSubmitResult.success) {
        _applyImmediateCheckInUi();
        _snack('บันทึกเวลาเข้างานเรียบร้อยแล้ว');
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.alreadyDone) {
        _applyImmediateAlreadyCheckedInUi();
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.manualRequired) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.previousAttendancePending) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.shiftSelectionRequired) {
        await _loadHelperTodayShifts(silent: true);
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.checkedInOtherClinic) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.multipleOpenSessions) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.locationUnavailable ||
          result == _AttendanceSubmitResult.locationPermissionDenied ||
          result == _AttendanceSubmitResult.locationServiceDisabled) {
        await _refreshAttendanceToday(silent: true);
        if (_attLocationError.trim().isNotEmpty) {
          _snack(_attLocationError.trim());
        }
      } else {
        await _refreshAttendanceToday(silent: true);
      }
    } finally {
      _resetAttendanceUiPhase();
      _attActionLock = false;
      print('[ATTENDANCE][CHECKIN] FINALLY');
    }
  }
    Future<void> _scanAndCheckOut() async {
    _tapLog('SCAN_CHECKOUT');
    print('[ATTENDANCE] ROLE=$_role clinicId=$_clinicId staffId=$_staffId');

    if (_attActionLock || _attBusy) {
      _snack('กรุณารอสักครู่ ระบบกำลังดำเนินการ');
      print('[ATTENDANCE][CHECKOUT] BLOCKED busy/actionLock');
      return;
    }
    _attActionLock = true;

    try {
      if (_ctxLoading) {
        print('[ATTENDANCE][CHECKOUT] BLOCKED ctxLoading=$_ctxLoading');
        _snack('กำลังเตรียมข้อมูล กรุณาลองอีกครั้ง');
        return;
      }

      if (!_isAttendanceUser) {
        _snack('เมนูนี้สำหรับพนักงานหรือผู้ช่วยเท่านั้น');
        return;
      }

      if (!_attendancePremiumEnabled) {
        _snack('ฟีเจอร์นี้สำหรับแพ็กเกจพรีเมียม');
        return;
      }

      if (_hasPreviousPendingBlock) {
        final label = _previousPendingSessionLabel();
        await _showPreviousAttendancePendingDialog(
          title: 'ยังมีรายการวันก่อนค้างอยู่',
          message: label.isNotEmpty
              ? 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่\n$label\n\nกรุณาแก้ไขและรออนุมัติก่อน จึงจะเริ่มลงเวลาวันใหม่ได้'
              : 'ยังมีรายการลงเวลาจากวันก่อนค้างอยู่ กรุณาแก้ไขและรออนุมัติก่อน จึงจะเริ่มลงเวลาวันใหม่ได้',
          previousSessionId: _attPreviousSessionId,
          previousWorkDate: _attPreviousWorkDate,
          previousShiftId: _attPreviousShiftId,
          previousClinicName: _attPreviousClinicName,
        );
        return;
      }

      if (_isHelper && !_helperCanProceedScan()) {
        return;
      }

      if (!_attCheckedIn) {
        _snack(
          _isHelper && _selectedHelperShiftId.isNotEmpty
              ? 'กะนี้ยังไม่ได้เช็คอิน'
              : 'วันนี้คุณยังไม่ได้เช็คอิน',
        );
        return;
      }

      if (_attCheckedOut) {
        _snack(
          _isHelper && _selectedHelperShiftId.isNotEmpty
              ? 'กะนี้เช็คเอาท์แล้ว'
              : 'วันนี้คุณเช็คเอาท์แล้ว',
        );
        return;
      }

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingOutBio,
        progressText: _isHelper
            ? (_selectedHelperShift == null
                ? 'กรุณาเลือกกะก่อน แล้วสแกนลายนิ้วมือ'
                : 'กำลังเช็คเอาท์สำหรับกะ: $_selectedHelperShiftLabel')
            : 'กรุณาสแกนลายนิ้วมือ',
        clearErr: true,
      );

      print('[ATTENDANCE][CHECKOUT] BEFORE BIO');
      final okBio = await _biometricAuthenticate();
      print('[ATTENDANCE][CHECKOUT] AFTER BIO ok=$okBio');

      if (!okBio) return;

      Position? position;
      if (_attendanceNeedsLiveLocation) {
        _setAttendanceUiPhase(
          _AttendanceUiPhase.checkingOutSubmit,
          progressText: 'กำลังตรวจสอบตำแหน่งปัจจุบัน',
          clearErr: true,
        );

        position = await _readAttendancePosition();
        if (position == null) {
          return;
        }
      }

      final token = await _getTokenAny();
      print(
        '[ATTENDANCE][CHECKOUT] TOKEN exists=${token != null && token.isNotEmpty}',
      );

      if (token == null || token.isEmpty) {
        _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
        return;
      }

      _setAttendanceUiPhase(
        _AttendanceUiPhase.checkingOutSubmit,
        progressText: _isHelper
            ? 'กำลังตรวจสอบ session ของกะที่เลือกและบันทึกเวลา'
            : (_attendanceNeedsLiveLocation
                ? 'กำลังตรวจสอบตำแหน่งและบันทึกเวลา'
                : 'กำลังบันทึกข้อมูล'),
      );
      _startSlowNetworkHint();

      print('[ATTENDANCE][CHECKOUT] BEFORE POST');
      final result = await _postAttendanceCheckOut(
        token: token,
        position: position,
      );
      print('[ATTENDANCE][CHECKOUT] RESULT=$result');

      if (result == _AttendanceSubmitResult.success) {
        _applyImmediateCheckOutUi();
        _snack('บันทึกเวลาออกงานเรียบร้อยแล้ว');
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.alreadyDone) {
        _applyImmediateAlreadyCheckedOutUi();
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.manualRequired) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.previousAttendancePending) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.earlyCheckoutReasonRequired) {
        _resetAttendanceUiPhase();

        final reason = await _showEarlyCheckoutReasonDialog();
        if (reason == null) {
          await _refreshAttendanceToday(silent: true);
          return;
        }

        Position? retryPosition = position;
        if (_attendanceNeedsLiveLocation && retryPosition == null) {
          _setAttendanceUiPhase(
            _AttendanceUiPhase.checkingOutSubmit,
            progressText: 'กำลังตรวจสอบตำแหน่งปัจจุบัน',
            clearErr: true,
          );
          retryPosition = await _readAttendancePosition();
          if (retryPosition == null) {
            await _refreshAttendanceToday(silent: true);
            return;
          }
        }

        _setAttendanceUiPhase(
          _AttendanceUiPhase.checkingOutSubmit,
          progressText: _attendanceNeedsLiveLocation
              ? 'กำลังตรวจสอบตำแหน่งและบันทึกข้อมูลพร้อมเหตุผล'
              : 'กำลังบันทึกข้อมูลพร้อมเหตุผล',
          clearErr: true,
        );
        _startSlowNetworkHint();

        final retry = await _postAttendanceCheckOut(
          token: token,
          reasonCode: reason['reasonCode'],
          reasonText: reason['reasonText'],
          note: reason['note'],
          position: retryPosition,
        );

        print('[ATTENDANCE][CHECKOUT] RETRY RESULT=$retry');
        if (retry == _AttendanceSubmitResult.success) {
          _applyImmediateCheckOutUi();
          _snack('บันทึกเวลาออกงานเรียบร้อยแล้ว');
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.alreadyDone) {
          _applyImmediateAlreadyCheckedOutUi();
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.manualRequired) {
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.previousAttendancePending) {
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.shiftSelectionRequired) {
          await _loadHelperTodayShifts(silent: true);
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.checkedInOtherClinic) {
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.multipleOpenSessions) {
          await _refreshAttendanceToday(silent: true);
        } else if (retry == _AttendanceSubmitResult.locationUnavailable ||
            retry == _AttendanceSubmitResult.locationPermissionDenied ||
            retry == _AttendanceSubmitResult.locationServiceDisabled) {
          await _refreshAttendanceToday(silent: true);
          if (_attLocationError.trim().isNotEmpty) {
            _snack(_attLocationError.trim());
          }
        } else {
          await _refreshAttendanceToday(silent: true);
        }
      } else if (result == _AttendanceSubmitResult.shiftSelectionRequired) {
        await _loadHelperTodayShifts(silent: true);
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.checkedInOtherClinic) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.multipleOpenSessions) {
        await _refreshAttendanceToday(silent: true);
      } else if (result == _AttendanceSubmitResult.locationUnavailable ||
          result == _AttendanceSubmitResult.locationPermissionDenied ||
          result == _AttendanceSubmitResult.locationServiceDisabled) {
        await _refreshAttendanceToday(silent: true);
        if (_attLocationError.trim().isNotEmpty) {
          _snack(_attLocationError.trim());
        }
      } else {
        await _refreshAttendanceToday(silent: true);
      }
    } finally {
      _resetAttendanceUiPhase();
      _attActionLock = false;
      print('[ATTENDANCE][CHECKOUT] FINALLY');
    }
  }

  Future<void> _openAttendanceHistory() async {
    _tapLog('OPEN_ATTENDANCE_HISTORY');

    if (_ctxLoading) return;
    if (!_isAttendanceUser) {
      _snack('เมนูนี้สำหรับพนักงานหรือผู้ช่วยเท่านั้น');
      return;
    }
    if (!_attendancePremiumEnabled) {
      _snack('ฟีเจอร์นี้สำหรับแพ็กเกจพรีเมียม');
      return;
    }

    final token = await _getTokenAny();
    if (token == null || token.isEmpty) {
      _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceHistoryScreen(
          token: token,
          role: _role,
          clinicId: _clinicId,
          staffId: _staffId,
          initialShiftId: _isHelper ? _selectedHelperShiftId : '',
          initialShiftLabel: _isHelper ? _selectedHelperShiftLabel : '',
        ),
      ),
    );

    if (_attendancePremiumEnabled && _isAttendanceUser && !_attBusy) {
      if (_isHelper) {
        await _loadHelperTodayShifts(silent: true);
      }
      await _refreshAttendanceToday();
    }
  }

  Future<void> _loadClosedMonthsForEmployee() async {
    if (_ctxLoading) return;

    if (!mounted) return;
    setState(() {
      _payslipLoading = true;
      _payslipErr = '';
      _closedMonths = [];
    });

    try {
      final token = await _getTokenAny();
      if (token == null || token.isEmpty) throw Exception('no token');

      final staffId = _staffId.trim();
      if (staffId.isEmpty) throw Exception('missing staffId');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      Uri u = _payrollUri('/payroll-close/close-months/$staffId');
      http.Response res = await _tryGet(u, headers: headers);

      if (res.statusCode == 404) {
        u = _payrollUri('/api/payroll-close/close-months/$staffId');
        res = await _tryGet(u, headers: headers);
      }

      if (res.statusCode != 200) {
        throw Exception('bad status ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      final rowsAny = (decoded is Map) ? decoded['rows'] : null;
      final rows = (rowsAny is List) ? rowsAny : const [];

      final list = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _payslipLoading = false;
        _payslipErr = '';
        _closedMonths = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _payslipLoading = false;
        _payslipErr = _friendlyAuthError(e);
        _closedMonths = [];
      });
    }
  }

  Future<void> _openPayslipMonth(String month) async {
    _tapLog('OPEN_PAYSLIP_MONTH $month');

    final token = await _getTokenAny();
    if (token == null || token.isEmpty) {
      _snack('เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
      return;
    }
    final staffId = _staffId.trim();
    if (staffId.isEmpty) {
      _snack('ไม่พบข้อมูลพนักงาน กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PayslipMonthDetailScreen(
          token: token,
          staffId: staffId,
          month: month,
        ),
      ),
    );

    await _loadClosedMonthsForEmployee();
  }

  Future<void> _openEmployeePayslipPicker() async {
    _tapLog('MY_EMP_PAYSLIP');

    if (_openingPayslipPicker) {
      _snack('กำลังเปิดรายการสลิปเงินเดือน กรุณารอสักครู่');
      return;
    }

    if (!_isEmployee) {
      _snack('เมนูนี้สำหรับพนักงานเท่านั้น');
      return;
    }

    final staffId = _staffId.trim();
    if (staffId.isEmpty) {
      _snack('ไม่พบข้อมูลพนักงาน กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่');
      return;
    }

    _openingPayslipPicker = true;
    try {
      await _loadClosedMonthsForEmployee();
      if (!mounted) return;

      if (_payslipErr.trim().isNotEmpty) {
        _snack(_payslipErr.trim());
        return;
      }

      final months = _closedMonths
          .map((e) => (e['month'] ?? '').toString().trim())
          .where((m) => m.isNotEmpty)
          .toList();

      if (months.isEmpty) {
        _snack('ขณะนี้ยังไม่มีงวดเงินเดือนที่ปิดแล้ว');
        return;
      }

      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text(
                    'เลือกงวดเงินเดือนที่ต้องการดู',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                ...months.map((m) {
                  return ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text('งวด $m'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, m),
                  );
                }),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      );

      if (picked != null && picked.isNotEmpty) {
        await _openPayslipMonth(picked);
      }
    } finally {
      _openingPayslipPicker = false;
    }
  }

  Future<void> _checkAttendanceLocationNow() async {
    _tapLog('CHECK_ATTENDANCE_LOCATION_NOW');

    if (_checkingAttendanceLocation) {
      _snack('กำลังตรวจสอบตำแหน่ง กรุณารอสักครู่');
      return;
    }

    if (!_isEmployee && !_isAttendanceUser) {
      _snack('เมนูนี้สำหรับผู้ใช้งานการลงเวลาเท่านั้น');
      return;
    }

    if (!_attendancePremiumEnabled) {
      _snack('ฟีเจอร์นี้สำหรับแพ็กเกจพรีเมียม');
      return;
    }

    if (!_attendanceNeedsLiveLocation) {
      _snack('บัญชีนี้ไม่จำเป็นต้องตรวจตำแหน่งก่อนลงเวลา');
      return;
    }

    _checkingAttendanceLocation = true;
    try {
      final pos = await _readAttendancePosition();
      if (pos == null) return;

      final accText = pos.accuracy.isFinite
          ? ' ความแม่นยำประมาณ ${pos.accuracy.toStringAsFixed(0)} เมตร'
          : '';

      _snack('ตรวจพบตำแหน่งเรียบร้อยแล้ว$accText');
    } finally {
      _checkingAttendanceLocation = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _oneLineNeed(Map<String, dynamic> n) {
    final title = (n['title'] ?? 'ต้องการผู้ช่วย').toString();
    final date = (n['date'] ?? '').toString();
    final start = (n['start'] ?? '').toString();
    final end = (n['end'] ?? '').toString();
    final rate = (n['hourlyRate'] ?? n['rate'] ?? '').toString();
    final requiredCount = (n['requiredCount'] ?? 1).toString();
    final pieces = <String>[
      if (date.isNotEmpty) date,
      if (start.isNotEmpty || end.isNotEmpty) '$start-$end',
      if (rate.isNotEmpty) '฿$rate/ชม.',
      'ต้องการ $requiredCount คน',
    ];
    return '$title • ${pieces.join(' • ')}';
  }

  Widget _urgentCardCompact() {
    return UrgentJobsCard(
      visible: _isClinic || _isHelper,
      loading: _urgentLoading,
      errText: _urgentErr,
      count: _urgentCount,
      line: (_urgentFirst == null) ? '' : _oneLineNeed(_urgentFirst!),
      isClinic: _isClinic,
      onRefresh: _refreshUrgentCardOnly,
      onOpenList: _isHelper ? _openHelperOpenNeeds : _openClinicNeedsMarket,
    );
  }

  Widget _policyCard() {
    if (!_isAttendanceUser) return const SizedBox.shrink();
    if (!_policyHumanReadableEnabled) return const SizedBox.shrink();

    return PolicyCard(
      loading: _policyLoading,
      errText: _policyErr,
      lines: _policyLines,
      isHelper: _isHelper,
      onRetry: _loadClinicPolicy,
    );
  }

  Widget _helperShiftSelectionCard() {
    if (!_isHelper) return const SizedBox.shrink();
    if (!_attendancePremiumEnabled) return const SizedBox.shrink();

    final hasShifts = _helperTodayShifts.isNotEmpty;
    final canPick = !_helperShiftLoading && hasShifts;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'เลือกกะที่จะใช้สแกนลายนิ้วมือ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _helperShiftSummaryLine(),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if (_helperHasMultipleShifts) ...[
              const SizedBox(height: 6),
              Text(
                'วันนี้มีหลายกะงาน กรุณาเลือกกะที่กำลังทำอยู่จริงก่อนสแกน',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_selectedHelperShift != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'กะที่เลือกอยู่',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedHelperShiftLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _helperShiftLoading ? null : _showHelperShiftPicker,
                    icon: _helperShiftLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.work_outline),
                    label: Text(
                      hasShifts
                          ? (_selectedHelperShift == null
                              ? 'เลือกกะงาน'
                              : 'เปลี่ยนกะงาน')
                          : 'ดูกะงานวันนี้',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _helperShiftLoading
                      ? null
                      : () => _loadHelperTodayShifts(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('รีเฟรช'),
                ),
              ],
            ),
            if (!canPick &&
                !_helperShiftLoading &&
                _helperShiftErr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _helperShiftErr,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attendancePreviousPendingCard() {
    if (!_hasPreviousPendingBlock) return const SizedBox.shrink();

    final label = _previousPendingSessionLabel();

    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ยังมีรายการวันก่อนค้างอยู่',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.orange.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _attPreviousPendingMessage.trim().isNotEmpty
                  ? _attPreviousPendingMessage.trim()
                  : 'กรุณาแก้ไขรายการลงเวลาของวันก่อน และรอการอนุมัติก่อน จึงจะเริ่มลงเวลาวันใหม่ได้',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.orange.shade900,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openPreviousPendingManualFix,
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('แก้รายการวันก่อน'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _attBusy ? null : () => _refreshAttendanceToday(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('รีเฟรช'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attendancePremiumGateCard({bool compact = false}) {
    if (!_isAttendanceUser) return const SizedBox.shrink();

    final title = compact
        ? 'บริการบันทึกเวลาด้วยลายนิ้วมือ'
        : 'พรีเมียม: บันทึกเวลางานด้วยลายนิ้วมือ';

    final subtitle = _isHelper
        ? 'ผู้ช่วยสามารถเลือกกะงานก่อนเช็คอินและเช็คเอาท์ด้วยลายนิ้วมือ เพื่อให้ระบบคำนวณชั่วโมงทำงานจริงได้แม่นยำยิ่งขึ้น'
        : 'เช็คอินและเช็คเอาท์ด้วยลายนิ้วมือ พร้อมตรวจตำแหน่งปัจจุบัน เพื่อให้ระบบคำนวณชั่วโมงทำงานและ OT ได้อัตโนมัติ';

    return PremiumGateCard(
      loading: _premiumLoading || _policyLoading,
      enabled: _attendancePremiumEnabled,
      title: title,
      subtitle: subtitle,
      onUpgrade: () async {
        _tapLog('UPGRADE_PREMIUM_DIALOG');
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('เปิดใช้งานบริการพรีเมียม'),
            content: const Text(
              'ขณะนี้ระบบยังอยู่ในช่วงทดสอบและยังไม่เชื่อมต่อการชำระเงินจริง\nต้องการเปิดใช้งานฟีเจอร์บันทึกเวลาด้วยลายนิ้วมือหรือไม่',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('เปิดใช้งาน'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await _setPremiumAttendanceEnabled(true);
          _snack('เปิดใช้งานบริการพรีเมียมเรียบร้อยแล้ว');
        }
      },
    );
  }

  Widget _attendanceActionCard({String? header}) {
    if (!_isAttendanceUser) return const SizedBox.shrink();
    if (!_attendancePremiumEnabled) return const SizedBox.shrink();

    final helperHeader = _selectedHelperShift != null
        ? 'บันทึกเวลาทำงาน (ผู้ช่วย) • เลือกกะแล้ว'
        : 'บันทึกเวลาทำงาน (ผู้ช่วย)';

    String statusLine = _displayAttendanceStatusLine;
    if (_attLocationLoading && _attendanceNeedsLiveLocation) {
      statusLine = 'กำลังตรวจสอบตำแหน่งปัจจุบัน';
    } else if (_attLocationError.trim().isNotEmpty &&
        !_attCheckedIn &&
        !_isHelper) {
      statusLine = _attLocationError.trim();
    }

    return AttendanceCard(
      title: header ?? (_isHelper ? helperHeader : 'บันทึกเวลาทำงานวันนี้'),
      statusLine: statusLine,
      errText: _attErr,
      loading: _attLoading,
      posting: _attPosting,
      bioLoading: _bioLoading,
      checkedIn: _attCheckedIn,
      checkedOut: _attCheckedOut,
      onCheckIn: _scanAndCheckIn,
      onCheckOut: _scanAndCheckOut,
      onRefresh: () => _refreshAttendanceToday(),
      onOpenHistory: _openAttendanceHistory,
    );
  }

  Widget _homeTab() {
    if (_ctxLoading) return const Center(child: CircularProgressIndicator());

    if (_ctxErr.isNotEmpty) {
      return _errorBox(
        title: 'ยังไม่พร้อมใช้งาน',
        message: _ctxErr,
        onRetry: _bootstrapContext,
      );
    }

    final trustScoreCard = _isClinic
        ? Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'คะแนนความน่าเชื่อถือของผู้ช่วย',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ตรวจสอบคะแนน ประวัติ และความน่าเชื่อถือของผู้ช่วยก่อนยืนยันการจ้างงาน',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openTrustScoreFromHome,
                      icon: const Icon(Icons.verified),
                      label: const Text('ดูคะแนนผู้ช่วย'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openHelperMarketplaceForClinicTrustScore,
                      icon: const Icon(Icons.search),
                      label: const Text('ค้นหาผู้ช่วย'),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;

    final marketCard = (_isClinic || _isHelper)
        ? Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ตลาดงาน',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.local_hospital_outlined),
                    title: const Text('ประกาศงานของคลินิก'),
                    subtitle:
                        const Text('สร้าง ดู และจัดการประกาศงานของคลินิก'),
                    onTap: _openClinicNeedsMarket,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('งานว่างสำหรับผู้ช่วย'),
                    subtitle: const Text('ดูงานที่เปิดรับและสมัครงาน'),
                    onTap: _openHelperOpenNeeds,
                  ),
                ],
              ),
            ),
          )
        : null;

    return HomeTab(
      isAttendanceUser: _isAttendanceUser,
      attendancePremiumEnabled: _attendancePremiumEnabled,
      isEmployee: _isEmployee,
      isClinic: _isClinic,
      isHelper: _isHelper,
      premiumGateCard: _attendancePremiumGateCard(),
      attendanceCard: _attendanceActionCard(
        header: _isHelper ? 'บันทึกเวลาทำงาน (ผู้ช่วย)' : 'บันทึกเวลาทำงาน',
      ),
      policyCard: _policyCard(),
      payslipCard: const SizedBox.shrink(),
      urgentCard: _urgentCardCompact(),
      trustScoreCard: trustScoreCard,
      marketCard: marketCard,
      helperShiftCard: Column(
        children: [
          _attendancePreviousPendingCard(),
          if (_hasPreviousPendingBlock) const SizedBox(height: 12),
          _helperShiftSelectionCard(),
        ],
      ),
    );
  }

  Widget _myTab() {
    if (_ctxLoading) return const Center(child: CircularProgressIndicator());

    if (_ctxErr.isNotEmpty) {
      return _errorBox(
        title: 'ยังไม่พร้อมใช้งาน',
        message: _ctxErr,
        onRetry: _bootstrapContext,
      );
    }

    final clinicSection = _isClinic
        ? Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('หน้าหลักคลินิกของฉัน'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openMyClinic,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('ดูคะแนนผู้ช่วย'),
                  subtitle: const Text('ตรวจสอบประวัติและคะแนนก่อนจ้างงาน'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openTrustScoreFromHome,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.search),
                  title: const Text('ค้นหาผู้ช่วย'),
                  subtitle:
                      const Text('ค้นหาและเลือกผู้ช่วยเพื่อดูคะแนนก่อนจ้างงาน'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openHelperMarketplaceForClinicTrustScore,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('พรีวิวเงินเดือน'),
                  subtitle: const Text('ตรวจสอบยอดเงินเดือนก่อนปิดงวดจริง'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    _tapLog('OPEN_LOCAL_PAYROLL');
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LocalPayrollScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          )
        : null;

    final helperSection = _isHelper
        ? Card(
            child: Column(
              children: [
                if (_hasPreviousPendingBlock) ...[
                  ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: const Text('แก้รายการลงเวลาวันก่อน'),
                    subtitle: Text(
                      _attPreviousWorkDate.trim().isNotEmpty
                          ? 'พบรายการค้างของวันที่ ${_attPreviousWorkDate.trim()} แตะเพื่อส่งคำขอแก้ไข'
                          : 'ยังมีรายการลงเวลาวันก่อนค้างอยู่ แตะเพื่อส่งคำขอแก้ไข',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openPreviousPendingManualFix,
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('ข้อมูลของฉัน (ผู้ช่วย)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openMyHelper,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.work_outline),
                  title: const Text('งานว่าง'),
                  subtitle: const Text('ดูประกาศงานที่เปิดรับอยู่'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openHelperOpenNeeds,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('เลือกกะสำหรับสแกนลายนิ้วมือ'),
                  subtitle: Text(
                    _selectedHelperShift == null
                        ? 'ยังไม่ได้เลือกกะ'
                        : _selectedHelperShiftLabel,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      _attendancePremiumEnabled ? _showHelperShiftPicker : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_calendar_outlined),
                  title: const Text('คำขอแก้ไขเวลา'),
                  subtitle: Text(
                    _hasPreviousPendingBlock
                        ? 'มีรายการวันก่อนค้างอยู่ แตะเพื่อแก้ไขก่อน'
                        : (_attendancePremiumEnabled
                            ? 'ส่งคำขอเช็คอินย้อนหลัง ลืมเช็คเอาท์ หรือแก้ไขเวลา'
                            : 'เปิดแพ็กเกจพรีเมียมก่อนใช้งานเมนูนี้'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _hasPreviousPendingBlock
                      ? _openPreviousPendingManualFix
                      : (_attendancePremiumEnabled
                          ? _showManualRequestMenu
                          : null),
                ),
              ],
            ),
          )
        : null;

    final employeeSection = _isEmployee
        ? Card(
            child: Column(
              children: [
                if (_hasPreviousPendingBlock) ...[
                  ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: const Text('แก้รายการลงเวลาวันก่อน'),
                    subtitle: Text(
                      _attPreviousWorkDate.trim().isNotEmpty
                          ? 'พบรายการค้างของวันที่ ${_attPreviousWorkDate.trim()} แตะเพื่อส่งคำขอแก้ไข'
                          : 'ยังมีรายการลงเวลาวันก่อนค้างอยู่ แตะเพื่อส่งคำขอแก้ไข',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openPreviousPendingManualFix,
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('การตรวจตำแหน่งสำหรับลงเวลา'),
                  subtitle: Text(_formatAttendanceLocationSummary()),
                  trailing: _checkingAttendanceLocation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap:
                      (_attendancePremiumEnabled && !_checkingAttendanceLocation)
                          ? _checkAttendanceLocationNow
                          : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_calendar_outlined),
                  title: const Text('คำขอแก้ไขเวลา'),
                  subtitle: Text(
                    _hasPreviousPendingBlock
                        ? 'มีรายการวันก่อนค้างอยู่ แตะเพื่อแก้ไขก่อน'
                        : (_attendancePremiumEnabled
                            ? 'ส่งคำขอกรณีลืมเช็คเอาท์ เช็คเอาท์ก่อนเวลา หรือแก้ไขเวลา'
                            : 'เปิดแพ็กเกจพรีเมียมก่อนใช้งานเมนูนี้'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _hasPreviousPendingBlock
                      ? _openPreviousPendingManualFix
                      : (_attendancePremiumEnabled
                          ? _showManualRequestMenu
                          : null),
                ),
              ],
            ),
          )
        : null;

    return MyTab(
      isAttendanceUser: _isAttendanceUser,
      attendancePremiumEnabled: _attendancePremiumEnabled,
      hasBackendPolicy: _hasBackendPolicy,
      isClinic: _isClinic,
      isHelper: _isHelper,
      isEmployee: _isEmployee,
      premiumAttendanceEnabled: _premiumAttendanceEnabled,
      onOpenAttendanceHistory: _openAttendanceHistory,
      policyCard: _policyCard(),
      clinicSection: clinicSection,
      helperSection: helperSection,
      employeeSection: employeeSection,
      onTogglePremiumAttendance: (v) async => _setPremiumAttendanceEnabled(v),
      onLogout: _logout,
    );
  }

  Widget _errorBox({
    required String title,
    required String message,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(message, style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองใหม่'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setTab(int i) {
    _tapLog('BOTTOM_NAV_TAP -> $i');
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homeTab(),
      _myTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic Smart Staff'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรชข้อมูล',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _tapLog('APPBAR_REFRESH');
              _bootstrapContext();
            },
          ),
          IconButton(
            tooltip: 'อัปเดตข้อมูลล่าสุด',
            icon: _activeRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.flash_on),
            onPressed: _activeRefreshing ? null : _activeRefreshUrgent,
          ),
          IconButton(
            tooltip: 'ออกจากระบบ',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: IndexedStack(
          index: _tab,
          children: pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: _setTab,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'หน้าแรก',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'เมนูของฉัน',
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// ✅ Payslip Month Detail
/// ============================================================
class _PayslipMonthDetailScreen extends StatefulWidget {
  final String token;
  final String staffId;
  final String month;

  const _PayslipMonthDetailScreen({
    required this.token,
    required this.staffId,
    required this.month,
  });

  @override
  State<_PayslipMonthDetailScreen> createState() =>
      _PayslipMonthDetailScreenState();
}

class _PayslipMonthDetailScreenState extends State<_PayslipMonthDetailScreen> {
  bool _loading = true;
  String _err = '';
  Map<String, dynamic>? _row;

  Uri _payrollUri(String path) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  String _fmtMoney(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n.toStringAsFixed(0);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<http.Response> _tryGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
      _row = null;
    });

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

      Uri u = _payrollUri(
        '/payroll-close/close-month/${widget.staffId}/${widget.month}',
      );
      http.Response res = await _tryGet(u, headers: headers);

      if (res.statusCode == 404) {
        u = _payrollUri(
          '/api/payroll-close/close-month/${widget.staffId}/${widget.month}',
        );
        res = await _tryGet(u, headers: headers);
      }

      if (res.statusCode != 200) {
        throw Exception('bad status ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      final rowAny = (decoded is Map) ? decoded['row'] : null;
      if (rowAny is! Map) {
        throw Exception('invalid data');
      }

      setState(() {
        _loading = false;
        _err = '';
        _row = Map<String, dynamic>.from(rowAny);
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _err = 'ไม่สามารถโหลดข้อมูลได้ กรุณาลองใหม่อีกครั้ง';
        _row = null;
      });
    }
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _row;

    return Scaffold(
      appBar: AppBar(
        title: Text('สลิปเงินเดือนงวด ${widget.month}'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรชข้อมูล',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'ยังไม่พร้อมใช้งาน',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _err,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('ลองใหม่'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'สรุปรายการ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _kv(
                              'รายรับรวม',
                              '฿${_fmtMoney(r?['grossMonthly'])}',
                            ),
                            _kv(
                              'ภาษีหัก ณ ที่จ่าย',
                              '฿${_fmtMoney(r?['withheldTaxMonthly'])}',
                            ),
                            _kv(
                              'ประกันสังคม',
                              '฿${_fmtMoney(r?['ssoEmployeeMonthly'])}',
                            ),
                            _kv(
                              'กองทุนสำรองเลี้ยงชีพ',
                              '฿${_fmtMoney(r?['pvdEmployeeMonthly'])}',
                            ),
                            const Divider(height: 16),
                            _kv(
                              'รับสุทธิ',
                              '฿${_fmtMoney(r?['netPay'])}',
                              bold: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'รายละเอียด OT',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _kv(
                              'ค่า OT ที่รวมในงวดนี้',
                              '฿${_fmtMoney(r?['otPay'])}',
                            ),
                            _kv(
                              'เวลาที่อนุมัติรวม (นาที)',
                              '${(r?['otApprovedMinutes'] ?? 0)}',
                            ),
                            _kv(
                              'ชั่วโมงถ่วงน้ำหนัก',
                              '${(r?['otApprovedWeightedHours'] ?? 0)}',
                            ),
                            _kv(
                              'จำนวนรายการ',
                              '${(r?['otApprovedCount'] ?? 0)}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'องค์ประกอบของรายได้',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _kv(
                              'เงินเดือนหรือฐานค่าจ้าง',
                              '฿${_fmtMoney(r?['grossBase'])}',
                            ),
                            _kv('โบนัส', '฿${_fmtMoney(r?['bonus'])}'),
                            _kv(
                              'เงินเพิ่มอื่น ๆ',
                              '฿${_fmtMoney(r?['otherAllowance'])}',
                            ),
                            _kv(
                              'รายการหักอื่น ๆ',
                              '฿${_fmtMoney(r?['otherDeduction'])}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// ============================================================
/// ✅ Local Payroll
/// ============================================================
class LocalPayrollScreen extends StatefulWidget {
  const LocalPayrollScreen({super.key});

  @override
  State<LocalPayrollScreen> createState() => _LocalPayrollScreenState();
}

class _LocalPayrollScreenState extends State<LocalPayrollScreen> {
  List<EmployeeModel> employees = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await StorageService.loadEmployees();
    if (!mounted) return;
    setState(() {
      employees = data;
      isLoading = false;
    });
  }

  bool _isParttime(EmployeeModel e) =>
      e.employmentType.toLowerCase().trim() == 'parttime';

  String _subtitle(EmployeeModel e) {
    if (_isParttime(e)) {
      return 'พนักงานพาร์ตไทม์ • ${e.position} • ${e.hourlyWage.toStringAsFixed(0)} บาท/ชม.';
    }
    return 'พนักงานประจำ • ${e.position} • ฐาน ${e.baseSalary.toStringAsFixed(0)} บาท • โบนัส ${e.bonus.toStringAsFixed(0)} บาท • ขาด/ลา ${e.absentDays} วัน';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deleteEmployee(int index) async {
    final removed = employees[index];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบ “${removed.fullName}” ใช่หรือไม่'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบข้อมูล'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => employees.removeAt(index));
    await StorageService.saveEmployees(employees);
    await _refreshData();
    _snack('ลบข้อมูลของ ${removed.fullName} เรียบร้อยแล้ว');
  }

  Future<void> _goAddEmployee() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEmployeeScreen()),
    );
    await _refreshData();
  }

  Future<void> _openPayslipPreview(EmployeeModel emp) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PayslipPreviewScreen(emp: emp)),
    );
    await _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('พรีวิวเงินเดือน'),
        actions: [
          IconButton(
            tooltip: 'เพิ่มพนักงาน',
            onPressed: _goAddEmployee,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : employees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ยังไม่มีข้อมูลพนักงานที่บันทึกไว้'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _goAddEmployee,
                        icon: const Icon(Icons.add),
                        label: const Text('เพิ่มพนักงานคนแรก'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: ListView.builder(
                    itemCount: employees.length,
                    itemBuilder: (context, index) {
                      final emp = employees[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(emp.fullName),
                          subtitle: Text(_subtitle(emp)),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EmployeeDetailScreen(
                                  clinicId: '',
                                  employee: emp,
                                ),
                              ),
                            );
                            await _refreshData();
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'ดูหรือพิมพ์สลิปเงินเดือน (PDF)',
                                icon: const Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.red,
                                ),
                                onPressed: () => _openPayslipPreview(emp),
                              ),
                              IconButton(
                                tooltip: 'ลบข้อมูลพนักงาน',
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.grey,
                                ),
                                onPressed: () => _deleteEmployee(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}