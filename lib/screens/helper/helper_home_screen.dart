// lib/screens/helper/helper_home_screen.dart
//
// ✅ FULL FILE — HelperHomeScreen (clinic_smart_staff) — CLEAN SINGLE OPEN-NEEDS FLOW
// ----------------------------------------------------
// ✅ GOAL: ผู้ช่วย “ประกาศเวลาว่าง” ได้ครบ flow
// - เมนูแรก: ผู้ช่วยประกาศเวลาว่าง -> เข้า HelperAvailabilityScreen
// - เมนูสอง: งานว่าง (ตลาดงาน) -> เข้า HelperOpenNeedsScreen เพียงหน้าเดียว
// - เมนูสาม: งานของฉัน (Shifts + นำทาง)
// - ✅ NEW: ตั้งพิกัดของฉัน -> เข้า HelperLocationSettingsScreen
//
// ✅ THIS ROUND CLEANUP:
// - ✅ ลบ OpenNeedsScreen เก่าที่ซ้ำซ้อนออกจากไฟล์นี้
// - ✅ ลบ NeedDetailScreen เก่าที่ผูกกับ OpenNeedsScreen ออก
// - ✅ ให้ทุกจุดที่เข้า “งานว่าง” วิ่งไปหน้า HelperOpenNeedsScreen ตัวเดียว
//
// ✅ PRODUCTION CLEAN:
// - ไม่โชว์ clinicId/userId/staffId ใน UI
// - ไม่โชว์ข้อความ endpoint/เทคนิคใน subtitle/snack
//
// ✅ IMPORTANT FIX:
// - ✅ helper token บางแบบไม่มี staffId -> ห้ามโยน MISSING_PROFILE
// - ✅ เมนู “งานว่าง/งานของฉัน” ต้องเข้าได้ แม้ staffId ว่าง
//
// ✅ STABILITY PATCH:
// - กัน setState หลัง dispose
// - กันกด nav ซ้ำซ้อน
//
// ✅ UX PATCH:
// - ✅ หน้ารายละเอียดงานว่างใช้ HelperOpenNeedsScreen ตัวเดียว
// - ✅ หน้า “งานของฉัน” มีปุ่มโทรคลินิก + นำทาง
// - ✅ ปรับการ์ดงานของฉันให้อ่านง่ายขึ้น:
//      - แสดงชื่องาน + ชื่อคลินิกชัดเจน
//      - แสดงตำแหน่ง/ที่อยู่/ระยะทาง
//      - แสดงสถานะเป็น badge
//      - ปุ่มโทร/นำทางมี label
//      - ลด location/address ซ้ำ
//      - ✅ แยกหมวด งานวันนี้ / งานที่กำลังจะมาถึง / งานย้อนหลัง
//      - ✅ เพิ่มปุ่ม ดูรายละเอียด
//
// ✅ NEW UX:
// - ✅ เพิ่มเมนู “ตั้งพิกัดของฉัน” สำหรับผู้ช่วย
// - ✅ ส่ง helperLat/helperLng ไป backend ตอนโหลดงานของฉัน
//
// ✅ DEBUG PATCH (NEW)
// - ✅ เพิ่ม log ตรวจ helperLat/helperLng จาก SharedPreferences
// - ✅ เพิ่ม log path/query ที่ส่งไป backend
// - ✅ เพิ่ม log clinicLat/clinicLng ของแต่ละ shift
// - ✅ เพิ่ม log distanceKm/distanceText ของแต่ละ shift
// - ✅ ช่วยไล่ bug ระยะทางเพี้ยน เช่น 0,0 / lat-lng สลับ / range ผิด
//

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:clinic_smart_staff/screens/auth/auth_gate_screen.dart';
import 'package:clinic_smart_staff/screens/home/home_screen.dart';
import 'package:clinic_smart_staff/screens/helper_availability_screen.dart';
import 'package:clinic_smart_staff/screens/helper/helper_location_settings_screen.dart';
import 'package:clinic_smart_staff/screens/helper_open_needs_screen.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/services/location_engine.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';

class HelperHomeScreen extends StatefulWidget {
  final String clinicId;
  final String userId;

  /// อาจส่งมาว่างได้ (เช่นจาก Home/My shell)
  final String staffId;

  const HelperHomeScreen({
    super.key,
    required this.clinicId,
    required this.userId,
    required this.staffId,
  });

  @override
  State<HelperHomeScreen> createState() => _HelperHomeScreenState();
}

class _HelperHomeScreenState extends State<HelperHomeScreen> {
  bool _loading = true;
  String _err = '';

  String _clinicId = '';
  String _userId = '';
  String _staffId = '';

  static const _kRole = 'app_role';
  static const _kClinicId = 'app_clinic_id';
  static const _kUserId = 'app_user_id';
  static const _kStaffId = 'app_staff_id';

  final _authClient = ApiClient(baseUrl: ApiConfig.authBaseUrl);

  bool _disposed = false;
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  int _navIndex = 0;
  bool _navBusy = false;

  @override
  void initState() {
    super.initState();
    _clinicId = widget.clinicId;
    _userId = widget.userId;
    _staffId = widget.staffId.trim();
    _boot();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _clearAllAuth() async {
    await AuthStorage.clearToken();

    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kRole, _kClinicId, _kUserId, _kStaffId]) {
      await prefs.remove(k);
    }
  }

  Future<Map<String, dynamic>> _me() async {
    final data = await _authClient.get(ApiConfig.me, auth: true);
    if (data is Map && data['user'] is Map) {
      return (data['user'] as Map).cast<String, dynamic>();
    }
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  bool _isMissingProfileError(String raw) {
    final s = raw.toLowerCase();
    return s.contains('missing_profile') || s.contains('staffid');
  }

  Future<void> _boot() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      if (_staffId.isNotEmpty) {
        await _saveStaffId(_staffId);
        if (!mounted) return;
        _safeSetState(() => _loading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_kStaffId) ?? '').trim();
      if (saved.isNotEmpty) {
        _staffId = saved;
        if (!mounted) return;
        _safeSetState(() => _loading = false);
        return;
      }

      final token = await AuthStorage.getToken();
      if (token == null || token.trim().isEmpty || token.trim() == 'null') {
        throw Exception('AUTH_REQUIRED');
      }

      final userMap = await _me();

      final staffId =
          (userMap['staffId'] ?? userMap['staff_id'] ?? '').toString().trim();
      final clinicId =
          (userMap['clinicId'] ?? userMap['clinic_id'] ?? '').toString().trim();
      final userId =
          (userMap['userId'] ?? userMap['_id'] ?? userMap['id'] ?? '')
              .toString()
              .trim();

      _staffId = staffId;
      if (_staffId.isNotEmpty) {
        await _saveStaffId(_staffId);
      }

      if (clinicId.isNotEmpty) _clinicId = clinicId;
      if (userId.isNotEmpty) _userId = userId;

      if (!mounted) return;
      _safeSetState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;

      final raw = e.toString();

      if (_isMissingProfileError(raw)) {
        _safeSetState(() {
          _err = '';
          _loading = false;
        });
        return;
      }

      _safeSetState(() {
        _err = raw;
        _loading = false;
      });
    }
  }

  Future<void> _saveStaffId(String staffId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStaffId, staffId);
  }

  Future<void> _logout() async {
    await _clearAllAuth();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGateScreen()),
      (route) => false,
    );
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _openAvailability() async {
    debugPrint('[UI] tap: availability');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelperAvailabilityScreen()),
    );
  }

  Future<void> _openHelperLocationSettings() async {
    debugPrint('[UI] tap: helper location');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HelperLocationSettingsScreen(),
      ),
    );
  }

  Future<void> _openOpenNeeds() async {
    debugPrint('[UI] tap: bottom/open needs');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HelperOpenNeedsScreen(),
      ),
    );
  }

  Future<void> _openMyShifts() async {
    debugPrint('[UI] tap: bottom/my shifts');
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyShiftsScreen(staffId: _staffId)),
    );
  }

  Future<void> _onBottomTap(int i) async {
    if (_navBusy) return;
    _navBusy = true;

    try {
      _safeSetState(() => _navIndex = i);

      if (i == 0) {
        await _openMyShifts();
      } else if (i == 1) {
        await _openOpenNeeds();
      } else {
        await _logout();
      }
    } finally {
      _navBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _goHome(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'กลับหน้าแรก',
            icon: const Icon(Icons.home),
            onPressed: _goHome,
          ),
          title: const Text('ผู้ช่วยของฉัน'),
          actions: [
            IconButton(
              tooltip: 'รีเฟรช',
              onPressed: _boot,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'ออกจากระบบ',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _navIndex,
          onTap: _onBottomTap,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'งานของฉัน',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.work_outline),
              label: 'งานว่าง',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.logout),
              label: 'ออกจากระบบ',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _boot,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_err.isNotEmpty)
                      _ErrorCard(
                        err: _err,
                        onRetry: _boot,
                        onHome: _goHome,
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'การลงเวลาทำงาน',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'การเช็คอินและเช็คเอาท์ของผู้ช่วยย้ายไปใช้งานที่หน้าแรกแล้ว เพื่อให้มีจุดบันทึกเวลาทำงานเพียงจุดเดียว',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _goHome,
                                icon: const Icon(Icons.home),
                                label: const Text('กลับไปหน้าแรก'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'ตารางเวลาว่างของฉัน',
                      subtitle:
                          'ประกาศและแก้ไขเวลาว่าง เพื่อให้คลินิกเลือกจองงานได้',
                      icon: Icons.calendar_month,
                      iconColor: cs.primary,
                      onTap: _openAvailability,
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'งานว่างที่เปิดรับ',
                      subtitle:
                          'ดูรายการงานที่เปิดรับสมัครและสมัครงานได้ทันที',
                      icon: Icons.work_outline,
                      iconColor: cs.primary,
                      onTap: () async {
                        debugPrint('[UI] tap: open needs');
                        await _openOpenNeeds();
                      },
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'งานที่ได้รับของฉัน',
                      subtitle:
                          'ดูงานที่ได้รับแล้ว พร้อมโทรคลินิกและนำทางไปยังสถานที่ทำงาน',
                      icon: Icons.assignment_turned_in_outlined,
                      iconColor: cs.primary,
                      onTap: () async {
                        debugPrint('[UI] tap: my shifts');
                        await _openMyShifts();
                      },
                    ),
                    const SizedBox(height: 10),
                    _MenuCard(
                      title: 'ตั้งพิกัดของฉัน',
                      subtitle:
                          'ใช้สำหรับค้นหางานใกล้ตัวคุณและคำนวณระยะจากคลินิก',
                      icon: Icons.my_location,
                      iconColor: cs.primary,
                      onTap: _openHelperLocationSettings,
                    ),
                    const SizedBox(height: 6),
                    if (_staffId.isEmpty)
                      const Text(
                        'หมายเหตุ: บางบัญชีอาจแสดงข้อมูลบางส่วนได้ไม่ครบถ้วน แต่ยังสามารถใช้งานเมนูงานว่างและงานของฉันได้ตามปกติ',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        leading: Icon(icon, color: iconColor),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String err;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  const _ErrorCard({
    required this.err,
    required this.onRetry,
    required this.onHome,
  });

  String _friendly(String raw) {
    final s = raw.toLowerCase();

    if (s.contains('auth_required') ||
        s.contains('no token') ||
        s.contains('unauthorized') ||
        s.contains('401')) {
      return 'กรุณาเข้าสู่ระบบใหม่อีกครั้ง';
    }

    if (s.contains('missing_profile') || s.contains('staffid')) {
      return 'ระบบกำลังอัปเดตข้อมูลบัญชีของคุณ โดยคุณยังใช้งานเมนูหลักได้ตามปกติ';
    }

    if (s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('connection')) {
      return 'เชื่อมต่อไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง';
    }
    return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
  }

  @override
  Widget build(BuildContext context) {
    final msg = _friendly(err);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'เกิดข้อผิดพลาด',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(msg, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองใหม่'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onHome,
                    icon: const Icon(Icons.home),
                    label: const Text('กลับหน้าแรก'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MyShiftsScreen extends StatefulWidget {
  final String staffId;
  const MyShiftsScreen({super.key, required this.staffId});

  @override
  State<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends State<MyShiftsScreen> {
  final _payroll = ApiClient(baseUrl: ApiConfig.payrollBaseUrl);

  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _items = [];

  bool _disposed = false;
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  static const List<String> _helperLatKeys = [
    'helper_location_lat',
    'helperLat',
    'helper_lat',
    'user_location_lat',
  ];

  static const List<String> _helperLngKeys = [
    'helper_location_lng',
    'helperLng',
    'helper_lng',
    'user_location_lng',
  ];

  AppLocation? _helperLocation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<Map<String, dynamic>> _extractItems(dynamic resAny) {
    if (resAny is Map) {
      final v = resAny['items'];
      if (v is List) {
        return v
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
      final data = resAny['data'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
      if (data is Map && data['items'] is List) {
        final items2 = data['items'] as List;
        return items2
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
      }
    }
    return [];
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  String _fmtD(double? v, {int fixed = 6}) {
    if (v == null) return 'null';
    return v.toStringAsFixed(fixed);
  }

  bool _isValidLat(double? v) => v != null && v >= -90 && v <= 90;
  bool _isValidLng(double? v) => v != null && v >= -180 && v <= 180;

  void _logBlock(String title, List<String> lines) {
    debugPrint('========== $title ==========');
    for (final line in lines) {
      debugPrint(line);
    }
    debugPrint('================================');
  }

  double? _readDoubleFromPrefs(
    SharedPreferences prefs,
    List<String> keys,
  ) {
    for (final k in keys) {
      final obj = prefs.get(k);

      if (obj is double) return obj;
      if (obj is int) return obj.toDouble();
      if (obj is String) {
        final x = double.tryParse(obj.trim());
        if (x != null) return x;
      }
    }
    return null;
  }

  String _readDoubleSourceFromPrefs(
    SharedPreferences prefs,
    List<String> keys,
  ) {
    for (final k in keys) {
      final obj = prefs.get(k);

      if (obj is double || obj is int) return '$k(${obj.runtimeType})';
      if (obj is String) {
        final x = double.tryParse(obj.trim());
        if (x != null) return '$k(String)';
      }
    }
    return 'not_found';
  }

  Future<Map<String, double>?> _loadHelperLocationQuery() async {
    final prefs = await SharedPreferences.getInstance();

    final lat = _readDoubleFromPrefs(prefs, _helperLatKeys);
    final lng = _readDoubleFromPrefs(prefs, _helperLngKeys);

    final latSource = _readDoubleSourceFromPrefs(prefs, _helperLatKeys);
    final lngSource = _readDoubleSourceFromPrefs(prefs, _helperLngKeys);

    _logBlock('HELPER LOCATION FROM PREFS', [
      'staffId           : ${widget.staffId}',
      'helperLat keys    : ${_helperLatKeys.join(", ")}',
      'helperLng keys    : ${_helperLngKeys.join(", ")}',
      'helperLat source  : $latSource',
      'helperLng source  : $lngSource',
      'helperLat value   : ${_fmtD(lat)}',
      'helperLng value   : ${_fmtD(lng)}',
    ]);

    if (lat == null || lng == null) {
      _logBlock('HELPER LOCATION INVALID', [
        'reason            : helperLat/helperLng is null',
      ]);
      return null;
    }
    if (lat == 0 || lng == 0) {
      _logBlock('HELPER LOCATION INVALID', [
        'reason            : helperLat/helperLng is zero',
        'helperLat         : ${_fmtD(lat)}',
        'helperLng         : ${_fmtD(lng)}',
      ]);
      return null;
    }
    if (!_isValidLat(lat)) {
      _logBlock('HELPER LOCATION INVALID', [
        'reason            : helperLat out of range (-90..90)',
        'helperLat         : ${_fmtD(lat)}',
      ]);
      return null;
    }
    if (!_isValidLng(lng)) {
      _logBlock('HELPER LOCATION INVALID', [
        'reason            : helperLng out of range (-180..180)',
        'helperLng         : ${_fmtD(lng)}',
      ]);
      return null;
    }

    _logBlock('HELPER LOCATION READY', [
      'helperLat         : ${_fmtD(lat)}',
      'helperLng         : ${_fmtD(lng)}',
    ]);

    return {
      'helperLat': lat,
      'helperLng': lng,
    };
  }

  Future<String> _buildShiftsPathWithHelperLocation(String basePath) async {
    final loc = await _loadHelperLocationQuery();
    if (loc == null) {
      _logBlock('SHIFTS REQUEST PATH', [
        'basePath          : $basePath',
        'query             : (no helperLat/helperLng)',
        'finalPath         : $basePath',
      ]);
      return basePath;
    }

    final uri = Uri(
      path: basePath,
      queryParameters: {
        'helperLat': loc['helperLat']!.toString(),
        'helperLng': loc['helperLng']!.toString(),
      },
    );

    _logBlock('SHIFTS REQUEST PATH', [
      'basePath          : $basePath',
      'helperLat         : ${_fmtD(loc['helperLat'])}',
      'helperLng         : ${_fmtD(loc['helperLng'])}',
      'finalPath         : ${uri.toString()}',
    ]);

    return uri.toString();
  }

  double? _extractClinicLat(Map<String, dynamic> it) {
    return LocationEngine.extractClinicLocation(it)?.lat;
  }

  double? _extractClinicLng(Map<String, dynamic> it) {
    return LocationEngine.extractClinicLocation(it)?.lng;
  }

  String _locationLabelFromShift(Map<String, dynamic> it) {
    final clinicLoc = LocationEngine.extractClinicLocation(it);
    if (clinicLoc != null) {
      if (_s(clinicLoc.label).isNotEmpty) return _s(clinicLoc.label);
      if (_s(clinicLoc.district).isNotEmpty &&
          _s(clinicLoc.province).isNotEmpty) {
        return '${clinicLoc.district}, ${clinicLoc.province}';
      }
      if (_s(clinicLoc.province).isNotEmpty) return clinicLoc.province;
      if (_s(clinicLoc.district).isNotEmpty) return clinicLoc.district;
      if (_s(clinicLoc.address).isNotEmpty) return clinicLoc.address;
    }

    final clinic = it['clinic'];
    if (clinic is Map) {
      final label1 = _s(clinic['locationLabel'] ?? clinic['clinicLocationLabel']);
      if (label1.isNotEmpty) return label1;
    }

    final direct = _s(it['clinicLocationLabel'] ?? it['locationLabel']);
    if (direct.isNotEmpty) return direct;

    final district = _s(it['clinicDistrict'] ?? it['district']);
    final province = _s(it['clinicProvince'] ?? it['province']);

    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;

    return '';
  }

  String _distanceTextFromShift(Map<String, dynamic> it) {
    final explicit = _s(it['distanceText'] ?? it['distance_text']);
    if (explicit.isNotEmpty) return explicit;

    final computed = LocationEngine.resolveDistanceTextForItem(
      it,
      _helperLocation,
    );
    if (computed.isNotEmpty) return computed;

    final raw = it['distanceKm'] ?? it['distance_km'];
    if (raw == null) return '';

    final x = double.tryParse(raw.toString());
    if (x == null || x <= 0) return '';
    return LocationEngine.formatDistanceKm(x);
  }

  void _debugShiftDistanceItem(
    int index,
    Map<String, dynamic> it, {
    Map<String, double>? helperLoc,
  }) {
    final jobTitle = _jobTitleFromShift(it);
    final clinicName = _clinicNameFromShift(it);
    final clinicLat = _extractClinicLat(it);
    final clinicLng = _extractClinicLng(it);
    final distanceKm = _toD(it['distanceKm'] ?? it['distance_km']);
    final distanceText = _distanceTextFromShift(it);
    final locationLabel = _locationLabelFromShift(it);
    final clinicAddress = _clinicAddressFromShift(it);

    final warnings = <String>[];
    if (clinicLat == null || clinicLng == null) {
      warnings.add('clinicLat/clinicLng is null');
    }
    if (clinicLat == 0 || clinicLng == 0) {
      warnings.add('clinicLat/clinicLng is zero');
    }
    if (clinicLat != null && !_isValidLat(clinicLat)) {
      warnings.add('clinicLat out of range');
    }
    if (clinicLng != null && !_isValidLng(clinicLng)) {
      warnings.add('clinicLng out of range');
    }
    if (distanceKm != null && distanceKm > 3000) {
      warnings.add('distanceKm looks too large for domestic trip');
    }

    _logBlock('SHIFT DISTANCE DEBUG #$index', [
      'jobTitle           : $jobTitle',
      'clinicName         : $clinicName',
      'helperLat          : ${_fmtD(helperLoc?['helperLat'])}',
      'helperLng          : ${_fmtD(helperLoc?['helperLng'])}',
      'clinicLat          : ${_fmtD(clinicLat)}',
      'clinicLng          : ${_fmtD(clinicLng)}',
      'distanceKm         : ${distanceKm?.toStringAsFixed(3) ?? "null"}',
      'distanceText       : ${distanceText.isEmpty ? "(empty)" : distanceText}',
      'locationLabel      : ${locationLabel.isEmpty ? "(empty)" : locationLabel}',
      'clinicAddress      : ${clinicAddress.isEmpty ? "(empty)" : clinicAddress}',
      'status             : ${_s(it['status'])}',
      'warnings           : ${warnings.isEmpty ? "(none)" : warnings.join(" | ")}',
      'raw distance source: '
          'distanceKm=${it['distanceKm']} / distance_km=${it['distance_km']} / '
          'distanceText=${it['distanceText']} / distance_text=${it['distance_text']}',
    ]);
  }

  DateTime? _dateOnlyFromShift(Map<String, dynamic> it) {
    final date = _s(it['date']);
    if (date.isEmpty) return null;
    try {
      final dt = DateTime.parse(date);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      return null;
    }
  }

  int _minutesFromTime(String raw) {
    final s = raw.trim();
    if (s.isEmpty || !s.contains(':')) return 0;
    final parts = s.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  String _sectionKey(Map<String, dynamic> it) {
    final today = DateTime.now();
    final nowDate = DateTime(today.year, today.month, today.day);
    final dt = _dateOnlyFromShift(it);
    if (dt == null) return 'upcoming';

    if (dt.year == nowDate.year &&
        dt.month == nowDate.month &&
        dt.day == nowDate.day) {
      return 'today';
    }
    if (dt.isAfter(nowDate)) return 'upcoming';
    return 'past';
  }

  int _compareUpcoming(Map<String, dynamic> a, Map<String, dynamic> b) {
    final da = _dateOnlyFromShift(a);
    final db = _dateOnlyFromShift(b);

    if (da != null && db != null) {
      final c = da.compareTo(db);
      if (c != 0) return c;
    } else if (da != null) {
      return -1;
    } else if (db != null) {
      return 1;
    }

    final ta = _minutesFromTime(_s(a['start']));
    final tb = _minutesFromTime(_s(b['start']));
    if (ta != tb) return ta.compareTo(tb);

    final distA = _toD(a['distanceKm'] ?? a['distance_km']);
    final distB = _toD(b['distanceKm'] ?? b['distance_km']);
    if (distA != null && distB != null) {
      final c = distA.compareTo(distB);
      if (c != 0) return c;
    } else if (distA != null) {
      return -1;
    } else if (distB != null) {
      return 1;
    }

    return _s(a['createdAt']).compareTo(_s(b['createdAt']));
  }

  int _comparePast(Map<String, dynamic> a, Map<String, dynamic> b) {
    final da = _dateOnlyFromShift(a);
    final db = _dateOnlyFromShift(b);

    if (da != null && db != null) {
      final c = db.compareTo(da);
      if (c != 0) return c;
    } else if (da != null) {
      return -1;
    } else if (db != null) {
      return 1;
    }

    final ta = _minutesFromTime(_s(a['start']));
    final tb = _minutesFromTime(_s(b['start']));
    if (ta != tb) return tb.compareTo(ta);

    return _s(b['createdAt']).compareTo(_s(a['createdAt']));
  }

  String _statusThai(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'นัดหมายแล้ว';
    if (s == 'scheduled') return 'นัดหมายแล้ว';
    if (s == 'completed') return 'เสร็จสิ้น';
    if (s == 'cancelled') return 'ยกเลิก';
    if (s == 'approved') return 'อนุมัติแล้ว';
    if (s == 'pending') return 'รอดำเนินการ';
    if (s == 'rejected') return 'ไม่ผ่านการอนุมัติ';
    if (s == 'open') return 'เปิดรับอยู่';
    if (s == 'closed') return 'ปิดแล้ว';
    return raw;
  }

  Color _statusBgColor(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'completed') return Colors.green.shade50;
    if (s == 'cancelled') return Colors.red.shade50;
    if (s == 'pending') return Colors.orange.shade50;
    if (s == 'approved' || s == 'scheduled') return Colors.blue.shade50;
    return Colors.grey.shade100;
  }

  Color _statusTextColor(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'completed') return Colors.green.shade800;
    if (s == 'cancelled') return Colors.red.shade800;
    if (s == 'pending') return Colors.orange.shade800;
    if (s == 'approved' || s == 'scheduled') return Colors.blue.shade800;
    return Colors.grey.shade800;
  }

  String _clinicNameFromShift(Map<String, dynamic> it) {
    final name1 = _s(it['clinicName'] ?? it['clinic_name']);
    if (name1.isNotEmpty) return name1;

    final clinic = it['clinic'];
    if (clinic is Map) {
      final name2 = _s(clinic['name'] ?? clinic['clinicName']);
      if (name2.isNotEmpty) return name2;
    }

    return 'คลินิก';
  }

  String _clinicPhoneFromShift(Map<String, dynamic> it) {
    final phone1 = _s(it['clinicPhone'] ?? it['clinic_phone']);
    if (phone1.isNotEmpty) return phone1;

    final clinic = it['clinic'];
    if (clinic is Map) {
      final phone2 = _s(clinic['phone'] ?? clinic['clinicPhone']);
      if (phone2.isNotEmpty) return phone2;
    }

    return '';
  }

  String _clinicAddressFromShift(Map<String, dynamic> it) {
    final address1 = _s(it['clinicAddress'] ?? it['clinic_address']);
    if (address1.isNotEmpty) return address1;

    final clinic = it['clinic'];
    if (clinic is Map) {
      final address2 = _s(clinic['address'] ?? clinic['clinicAddress']);
      if (address2.isNotEmpty) return address2;
    }

    return '';
  }

  String _jobTitleFromShift(Map<String, dynamic> it) {
    final title = _s(it['title']);
    if (title.isNotEmpty) return title;

    final role = _s(it['role']);
    if (role.isNotEmpty) return role;

    final note = _s(it['note']);
    if (note.isNotEmpty && note.length <= 40) return note;

    return 'งานที่ได้รับ';
  }

  String _notePreview(Map<String, dynamic> it) {
    final note = _s(it['note']);
    final title = _s(it['title']);
    final role = _s(it['role']);

    if (note.isEmpty) return '';
    if (note == title || note == role) return '';
    return note;
  }

  bool _looksSameLocation(String a, String b) {
    final aa = a.replaceAll(' ', '').trim();
    final bb = b.replaceAll(' ', '').trim();
    if (aa.isEmpty || bb.isEmpty) return false;
    return aa == bb || aa.contains(bb) || bb.contains(aa);
  }

  Future<void> _callClinicFromShift(Map<String, dynamic> it) async {
    final phone = _clinicPhoneFromShift(it);

    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('คลินิกยังไม่มีเบอร์โทร')),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรได้')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรได้')),
      );
    }
  }

  String _pickTravelMode(Map<String, dynamic> it) {
    final raw = _s(
      it['travelMode'] ?? it['transportMode'] ?? it['mode'],
    );
    final m = raw.toLowerCase();
    if (m == 'w' || m == 'walk' || m == 'walking') return 'walk';
    if (m == 'd' || m == 'drive' || m == 'driving' || m == 'car') {
      return 'drive';
    }
    if (m == 'transit' || m == 'public' || m == 'bus' || m == 'train') {
      return 'transit';
    }

    final note = _s(it['note']).toLowerCase();
    final title = _s(it['title']).toLowerCase();
    final role = _s(it['role']).toLowerCase();
    final type = _s(it['type']).toLowerCase();
    final blob = '$note $title $role $type';

    if (blob.contains('รถสาธารณะ') ||
        blob.contains('transit') ||
        blob.contains('bts') ||
        blob.contains('mrt') ||
        blob.contains('bus') ||
        blob.contains('รถเมล์') ||
        blob.contains('รถไฟ')) {
      return 'transit';
    }

    if (blob.contains('เดิน') ||
        blob.contains('walk') ||
        blob.contains('walking') ||
        blob.contains('ใกล้') ||
        blob.contains('near')) {
      return 'walk';
    }

    return 'drive';
  }

  Future<void> _openNavFromShift(Map<String, dynamic> it) async {
    final clinicLoc = LocationEngine.extractClinicLocation(it);

    _logBlock('OPEN MAP DEBUG', [
      'jobTitle           : ${_jobTitleFromShift(it)}',
      'clinicName         : ${_clinicNameFromShift(it)}',
      'clinicLat          : ${_fmtD(clinicLoc?.lat)}',
      'clinicLng          : ${_fmtD(clinicLoc?.lng)}',
      'distanceKm         : ${_toD(it['distanceKm'] ?? it['distance_km'])?.toStringAsFixed(3) ?? "null"}',
      'distanceText       : ${_distanceTextFromShift(it)}',
    ]);

    if (clinicLoc == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('งานนี้ยังไม่มีพิกัดสำหรับนำทาง')),
      );
      return;
    }

    final lat = clinicLoc.lat;
    final lng = clinicLoc.lng;
    final mode = _pickTravelMode(it);

    final androidNav = Uri.parse(
      'google.navigation:q=$lat,$lng&mode=${mode == 'walk' ? 'w' : 'd'}',
    );

    final webDir = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
      '&travelmode=${mode == 'transit' ? 'transit' : (mode == 'walk' ? 'walking' : 'driving')}',
    );

    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');

    Future<bool> tryLaunch(Uri u) async {
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }

    if (mode == 'transit') {
      if (await tryLaunch(webDir)) return;
      if (await tryLaunch(geo)) return;
      if (await tryLaunch(androidNav)) return;
    } else {
      if (await tryLaunch(androidNav)) return;
      if (await tryLaunch(geo)) return;
      if (await tryLaunch(webDir)) return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('เปิดแผนที่ไม่ได้')),
    );
  }

  Future<void> _openShiftDetail(Map<String, dynamic> it) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyShiftDetailScreen(
          shift: it,
          onCallClinic: () => _callClinicFromShift(it),
          onOpenMap: () => _openNavFromShift(it),
        ),
      ),
    );
  }

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      final helperLocMap = await _loadHelperLocationQuery();
      final helperLocSaved = await SettingService.loadHelperLocation();
      _helperLocation = helperLocSaved;

      final shiftsPath = await _buildShiftsPathWithHelperLocation('/shifts');
      final apiShiftsPath =
          await _buildShiftsPathWithHelperLocation('/api/shifts');

      dynamic res;
      String usedPath = shiftsPath;

      try {
        res = await _payroll.get(shiftsPath, auth: true);
        usedPath = shiftsPath;
      } catch (e) {
        debugPrint('[SHIFTS] primary path failed => $e');
        res = await _payroll.get(apiShiftsPath, auth: true);
        usedPath = apiShiftsPath;
      }

      if (res is Map) {
        final ok = res['ok'];
        if (ok is bool && ok == false) {
          throw Exception(res['message'] ?? 'load shifts failed');
        }
      }

      final items = _extractItems(res);

      _logBlock('SHIFTS LOAD RESULT', [
        'usedPath          : $usedPath',
        'itemsCount        : ${items.length}',
        'helperLat         : ${_fmtD(helperLocMap?['helperLat'])}',
        'helperLng         : ${_fmtD(helperLocMap?['helperLng'])}',
      ]);

      for (var i = 0; i < items.length; i++) {
        _debugShiftDistanceItem(i, items[i], helperLoc: helperLocMap);
      }

      _safeSetState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[SHIFTS] load error => $e');
      _safeSetState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Widget _statusChip(String raw) {
    final text = _statusThai(raw);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _statusBgColor(raw),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _statusBgColor(raw)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _statusTextColor(raw),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _metaRow(
    IconData icon,
    String text, {
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    if (text.trim().isEmpty || text.trim() == '-') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? Colors.grey.shade800,
                fontWeight: fontWeight,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.purple.shade100),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: Colors.purple.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCard(Map<String, dynamic> it) {
    final jobTitle = _jobTitleFromShift(it);
    final clinicName = _clinicNameFromShift(it);
    final clinicPhone = _clinicPhoneFromShift(it);
    final clinicAddress = _clinicAddressFromShift(it);
    final locationLabel = _locationLabelFromShift(it);
    final distanceText = _distanceTextFromShift(it);

    final date = _s(it['date']);
    final start = _s(it['start']);
    final end = _s(it['end']);
    final rate = _s(it['hourlyRate']);
    final statusRaw = _s(it['status']);
    final notePreview = _notePreview(it);

    final locationLine = () {
      if (locationLabel.isNotEmpty && distanceText.isNotEmpty) {
        return '$locationLabel • ห่างจากคุณ $distanceText';
      }
      if (locationLabel.isNotEmpty) return locationLabel;
      if (distanceText.isNotEmpty) {
        return 'ห่างจากคุณ $distanceText';
      }
      return '';
    }();

    final showAddress = clinicAddress.isNotEmpty &&
        !_looksSameLocation(locationLine, clinicAddress);

    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.purple.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.assignment_turned_in_outlined,
                    color: Colors.purple.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jobTitle,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        clinicName,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(statusRaw),
              ],
            ),
            if (locationLine.isNotEmpty)
              _metaRow(
                Icons.location_on_outlined,
                locationLine,
                color: Colors.purple.shade700,
                fontWeight: FontWeight.w800,
              ),
            if (showAddress)
              _metaRow(
                Icons.place_outlined,
                clinicAddress,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            if (date.isNotEmpty || start.isNotEmpty || end.isNotEmpty)
              _metaRow(
                Icons.access_time,
                [
                  if (date.isNotEmpty) 'วันที่ $date',
                  if (start.isNotEmpty || end.isNotEmpty)
                    'เวลา $start - $end',
                ].join(' • '),
                color: Colors.deepPurple.shade700,
                fontWeight: FontWeight.w700,
              ),
            if (rate.isNotEmpty)
              _metaRow(
                Icons.payments_outlined,
                'ค่าตอบแทน $rate บาท/ชม.',
                color: Colors.green.shade700,
                fontWeight: FontWeight.w800,
              ),
            if (clinicPhone.isNotEmpty)
              _metaRow(
                Icons.phone_outlined,
                'เบอร์คลินิก $clinicPhone',
                color: Colors.blueGrey.shade700,
              ),
            if (notePreview.isNotEmpty)
              _metaRow(
                Icons.notes_outlined,
                notePreview,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                _actionButton(
                  onPressed: () => _callClinicFromShift(it),
                  icon: Icons.phone,
                  label: 'โทรคลินิก',
                ),
                const SizedBox(width: 10),
                _actionButton(
                  onPressed: () => _openNavFromShift(it),
                  icon: Icons.navigation,
                  label: 'ดูแผนที่',
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openShiftDetail(it),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('ดูรายละเอียด'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedList() {
    final todayItems = <Map<String, dynamic>>[];
    final upcomingItems = <Map<String, dynamic>>[];
    final pastItems = <Map<String, dynamic>>[];

    for (final item in _items) {
      final key = _sectionKey(item);
      if (key == 'today') {
        todayItems.add(item);
      } else if (key == 'past') {
        pastItems.add(item);
      } else {
        upcomingItems.add(item);
      }
    }

    todayItems.sort(_compareUpcoming);
    upcomingItems.sort(_compareUpcoming);
    pastItems.sort(_comparePast);

    final widgets = <Widget>[];

    void addSection(String title, List<Map<String, dynamic>> items) {
      if (items.isEmpty) return;
      widgets.add(_sectionHeader(title, items.length));
      for (var i = 0; i < items.length; i++) {
        widgets.add(_buildShiftCard(items[i]));
        if (i != items.length - 1) {
          widgets.add(const SizedBox(height: 12));
        }
      }
      widgets.add(const SizedBox(height: 8));
    }

    addSection('งานวันนี้', todayItems);
    addSection('งานที่กำลังจะมาถึง', upcomingItems);
    addSection('งานย้อนหลัง', pastItems);

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('งานที่ได้รับของฉัน'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _err.isNotEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ErrorCard(
                          err: _err,
                          onRetry: _load,
                          onHome: () => Navigator.pop(context),
                        ),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            SizedBox(height: 30),
                            Center(child: Text('ยังไม่มีงานที่ได้รับ')),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: _buildGroupedList(),
                        ),
            ),
    );
  }
}

class MyShiftDetailScreen extends StatelessWidget {
  final Map<String, dynamic> shift;
  final Future<void> Function() onCallClinic;
  final Future<void> Function() onOpenMap;

  const MyShiftDetailScreen({
    super.key,
    required this.shift,
    required this.onCallClinic,
    required this.onOpenMap,
  });

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _statusThai(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'นัดหมายแล้ว';
    if (s == 'scheduled') return 'นัดหมายแล้ว';
    if (s == 'completed') return 'เสร็จสิ้น';
    if (s == 'cancelled') return 'ยกเลิก';
    if (s == 'approved') return 'อนุมัติแล้ว';
    if (s == 'pending') return 'รอดำเนินการ';
    if (s == 'rejected') return 'ไม่ผ่านการอนุมัติ';
    if (s == 'open') return 'เปิดรับอยู่';
    if (s == 'closed') return 'ปิดแล้ว';
    return raw;
  }

  String _clinicNameFromShift(Map<String, dynamic> it) {
    final name1 = _s(it['clinicName'] ?? it['clinic_name']);
    if (name1.isNotEmpty) return name1;

    final clinic = it['clinic'];
    if (clinic is Map) {
      final name2 = _s(clinic['name'] ?? clinic['clinicName']);
      if (name2.isNotEmpty) return name2;
    }

    return 'คลินิก';
  }

  String _clinicPhoneFromShift(Map<String, dynamic> it) {
    final phone1 = _s(it['clinicPhone'] ?? it['clinic_phone']);
    if (phone1.isNotEmpty) return phone1;

    final clinic = it['clinic'];
    if (clinic is Map) {
      final phone2 = _s(clinic['phone'] ?? clinic['clinicPhone']);
      if (phone2.isNotEmpty) return phone2;
    }

    return '';
  }

  String _clinicAddressFromShift(Map<String, dynamic> it) {
    final address1 = _s(it['clinicAddress'] ?? it['clinic_address']);
    if (address1.isNotEmpty) return address1;

    final clinic = it['clinic'];
    if (clinic is Map) {
      final address2 = _s(clinic['address'] ?? clinic['clinicAddress']);
      if (address2.isNotEmpty) return address2;
    }

    return '';
  }

  String _locationLabelFromShift(Map<String, dynamic> it) {
    final clinicLoc = LocationEngine.extractClinicLocation(it);
    if (clinicLoc != null) {
      if (_s(clinicLoc.label).isNotEmpty) return _s(clinicLoc.label);
      if (_s(clinicLoc.district).isNotEmpty &&
          _s(clinicLoc.province).isNotEmpty) {
        return '${clinicLoc.district}, ${clinicLoc.province}';
      }
      if (_s(clinicLoc.province).isNotEmpty) return clinicLoc.province;
      if (_s(clinicLoc.district).isNotEmpty) return clinicLoc.district;
      if (_s(clinicLoc.address).isNotEmpty) return clinicLoc.address;
    }

    final clinic = it['clinic'];
    if (clinic is Map) {
      final label1 = _s(clinic['locationLabel'] ?? clinic['clinicLocationLabel']);
      if (label1.isNotEmpty) return label1;
    }

    final direct = _s(it['clinicLocationLabel'] ?? it['locationLabel']);
    if (direct.isNotEmpty) return direct;

    final district = _s(it['clinicDistrict'] ?? it['district']);
    final province = _s(it['clinicProvince'] ?? it['province']);

    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;

    return '';
  }

  String _distanceTextFromShift(Map<String, dynamic> it) {
    final explicit = _s(it['distanceText'] ?? it['distance_text']);
    if (explicit.isNotEmpty) return explicit;

    final raw = it['distanceKm'] ?? it['distance_km'];
    if (raw == null) return '';

    final x = double.tryParse(raw.toString());
    if (x == null || x <= 0) return '';
    return LocationEngine.formatDistanceKm(x);
  }

  String _jobTitleFromShift(Map<String, dynamic> it) {
    final title = _s(it['title']);
    if (title.isNotEmpty) return title;

    final role = _s(it['role']);
    if (role.isNotEmpty) return role;

    final note = _s(it['note']);
    if (note.isNotEmpty && note.length <= 40) return note;

    return 'งานที่ได้รับ';
  }

  Widget _infoRow(
    IconData icon,
    String text, {
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? Colors.grey.shade800,
                fontWeight: fontWeight,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobTitle = _jobTitleFromShift(shift);
    final clinicName = _clinicNameFromShift(shift);
    final clinicPhone = _clinicPhoneFromShift(shift);
    final clinicAddress = _clinicAddressFromShift(shift);
    final locationLabel = _locationLabelFromShift(shift);
    final distanceText = _distanceTextFromShift(shift);

    final date = _s(shift['date']);
    final start = _s(shift['start']);
    final end = _s(shift['end']);
    final rate = _s(shift['hourlyRate']);
    final note = _s(shift['note']);
    final role = _s(shift['role']);
    final statusText = _statusThai(_s(shift['status']));

    final locationLine = () {
      if (locationLabel.isNotEmpty && distanceText.isNotEmpty) {
        return '$locationLabel • ห่างจากคุณ $distanceText';
      }
      if (locationLabel.isNotEmpty) return locationLabel;
      if (distanceText.isNotEmpty) return 'ห่างจากคุณ $distanceText';
      return '';
    }();

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดงาน'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: Colors.purple.shade100),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    jobTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    clinicName,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _infoRow(
                    Icons.verified_outlined,
                    'สถานะ $statusText',
                    color: Colors.blueGrey.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                  if (locationLine.isNotEmpty)
                    _infoRow(
                      Icons.location_on_outlined,
                      locationLine,
                      color: Colors.purple.shade700,
                      fontWeight: FontWeight.w800,
                    ),
                  if (clinicAddress.isNotEmpty)
                    _infoRow(
                      Icons.place_outlined,
                      clinicAddress,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  if (date.isNotEmpty || start.isNotEmpty || end.isNotEmpty)
                    _infoRow(
                      Icons.access_time,
                      [
                        if (date.isNotEmpty) 'วันที่ $date',
                        if (start.isNotEmpty || end.isNotEmpty)
                          'เวลา $start - $end',
                      ].join(' • '),
                      color: Colors.deepPurple.shade700,
                      fontWeight: FontWeight.w800,
                    ),
                  if (rate.isNotEmpty)
                    _infoRow(
                      Icons.payments_outlined,
                      'ค่าตอบแทน $rate บาท/ชม.',
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w800,
                    ),
                  if (clinicPhone.isNotEmpty)
                    _infoRow(
                      Icons.phone_outlined,
                      'เบอร์คลินิก $clinicPhone',
                      color: Colors.blueGrey.shade700,
                    ),
                  if (role.isNotEmpty)
                    _infoRow(
                      Icons.badge_outlined,
                      'ตำแหน่งงาน $role',
                      color: Colors.grey.shade700,
                    ),
                  if (note.isNotEmpty)
                    _infoRow(
                      Icons.notes_outlined,
                      note,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCallClinic,
                          icon: const Icon(Icons.phone),
                          label: const Text('โทรคลินิก'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onOpenMap,
                          icon: const Icon(Icons.navigation),
                          label: const Text('ดูแผนที่'),
                        ),
                      ),
                    ],
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