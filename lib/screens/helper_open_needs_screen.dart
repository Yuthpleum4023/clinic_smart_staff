import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/widgets/apply_success_dialog.dart';

class HelperOpenNeedsScreen extends StatefulWidget {
  const HelperOpenNeedsScreen({super.key});

  @override
  State<HelperOpenNeedsScreen> createState() => _HelperOpenNeedsScreenState();
}

class _HelperOpenNeedsScreenState extends State<HelperOpenNeedsScreen> {
  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _items = [];

  final TextEditingController _phoneCtrl = TextEditingController();

  String _actingId = '';
  bool _disposed = false;

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  @override
  void dispose() {
    _disposed = true;
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^\d]'), '');

  double _d(dynamic v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fallback;
  }

  double? _dNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final t = '$v'.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  bool _b(dynamic v) {
    if (v is bool) return v;
    final s = _s(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  String _money(double n) {
    if (n <= 0) return '0';
    if (n == n.roundToDouble()) return n.toStringAsFixed(0);
    return n.toStringAsFixed(2);
  }

  String _formatDateThai(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '-';

    final dt = DateTime.tryParse(s);
    if (dt == null) return s;

    const months = [
      '',
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year + 543}';
  }

  bool _isUrgent(Map<String, dynamic> m) {
    final urgent = _b(m['urgent']) || _b(m['isUrgent']) || _b(m['hot']);
    final priority = _s(m['priority']).toLowerCase();
    final type = _s(m['type']).toLowerCase();

    return urgent || priority == 'urgent' || type == 'urgent';
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final t = _s(v);
      if (t.isNotEmpty && t.toLowerCase() != 'null') return t;
    }
    return '';
  }

  String _distanceText(Map<String, dynamic> m) {
    final explicit = _s(
      m['distanceText'] ??
          m['clinicDistanceText'] ??
          m['distance_text'] ??
          m['distance'],
    );
    if (explicit.isNotEmpty) return explicit;

    final kmRaw = m['distanceKm'] ?? m['clinicDistanceKm'] ?? m['distance_km'];
    if (kmRaw == null) return '';

    final km = _d(kmRaw, -1);
    if (km < 0) return '';
    if (km < 10) return '${km.toStringAsFixed(1)} กม.';
    return '${km.round()} กม.';
  }

  String _locationLabel(Map<String, dynamic> m) {
    final district = _firstNonEmpty([
      m['clinicDistrict'],
      m['district'],
      m['amphoe'],
      m['area'],
      m['subDistrict'],
    ]);

    final province = _firstNonEmpty([
      m['clinicProvince'],
      m['province'],
      m['changwat'],
      m['state'],
    ]);

    final explicit = _firstNonEmpty([
      m['clinicLocationLabel'],
      m['locationLabel'],
      m['location_label'],
    ]);

    final address = _firstNonEmpty([
      m['clinicAddress'],
      m['address'],
      m['formattedAddress'],
      m['displayAddress'],
    ]);

    if (explicit.isNotEmpty) return explicit;
    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    if (address.isNotEmpty) return address;
    return '';
  }

  String _locationDistanceLine(Map<String, dynamic> m) {
    final loc = _locationLabel(m);
    final dist = _distanceText(m);

    if (loc.isNotEmpty && dist.isNotEmpty) {
      return '$loc • ห่างจากคุณ $dist';
    }
    if (dist.isNotEmpty) {
      return 'ห่างจากคุณ $dist';
    }
    if (loc.isNotEmpty) return loc;
    return '';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<String?> _getToken() async {
    try {
      final t = await AuthStorage.getToken();
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return token;
  }

  Uri _u(String path, {Map<String, dynamic>? query}) {
    final base = ApiConfig.payrollBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');

    if (query == null || query.isEmpty) return uri;

    final qp = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      final text = '$value'.trim();
      if (text.isEmpty) return;
      qp[key] = text;
    });

    return uri.replace(queryParameters: qp.isEmpty ? null : qp);
  }

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _readLocationSnapshot() async {
    final prefs = await SharedPreferences.getInstance();

    String? readString(List<String> keys) {
      for (final k in keys) {
        final v = prefs.getString(k);
        if (v != null && v.trim().isNotEmpty && v.trim() != 'null') {
          return v.trim();
        }
      }
      return null;
    }

    double? readDouble(List<String> keys) {
      for (final k in keys) {
        final dv = prefs.getDouble(k);
        if (dv != null) return dv;

        final sv = prefs.getString(k);
        final parsed = _dNull(sv);
        if (parsed != null) return parsed;

        final iv = prefs.getInt(k);
        if (iv != null) return iv.toDouble();
      }
      return null;
    }

    Map<String, dynamic> parseJsonString(String raw) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      return {};
    }

    final rawMap = <String, dynamic>{};

    const mapKeys = [
      'userLocation',
      'selectedLocation',
      'helperLocation',
      'currentLocation',
      'locationSnapshot',
      'profileLocation',
      'sellerLocation',
      'clinicLocation',
    ];

    for (final k in mapKeys) {
      final raw = prefs.getString(k);
      if (raw != null && raw.trim().isNotEmpty) {
        rawMap.addAll(parseJsonString(raw));
      }
    }

    final lat = readDouble([
          'lat',
          'latitude',
          'userLat',
          'currentLat',
          'selectedLat',
          'helperLat',
          'profileLat',
        ]) ??
        _dNull(rawMap['lat']) ??
        _dNull(rawMap['latitude']);

    final lng = readDouble([
          'lng',
          'lon',
          'longitude',
          'userLng',
          'currentLng',
          'selectedLng',
          'helperLng',
          'profileLng',
        ]) ??
        _dNull(rawMap['lng']) ??
        _dNull(rawMap['lon']) ??
        _dNull(rawMap['longitude']);

    return {
      'lat': lat,
      'lng': lng,
      'district': _firstNonEmpty([
        readString([
          'district',
          'currentDistrict',
          'selectedDistrict',
          'helperDistrict',
          'profileDistrict',
        ]),
        rawMap['district']?.toString(),
        rawMap['subDistrict']?.toString(),
        rawMap['amphoe']?.toString(),
        rawMap['area']?.toString(),
      ]),
      'province': _firstNonEmpty([
        readString([
          'province',
          'currentProvince',
          'selectedProvince',
          'helperProvince',
          'profileProvince',
        ]),
        rawMap['province']?.toString(),
        rawMap['changwat']?.toString(),
        rawMap['state']?.toString(),
      ]),
      'address': _firstNonEmpty([
        readString([
          'address',
          'currentAddress',
          'selectedAddress',
          'helperAddress',
          'profileAddress',
          'formattedAddress',
        ]),
        rawMap['address']?.toString(),
        rawMap['formattedAddress']?.toString(),
        rawMap['displayName']?.toString(),
        rawMap['label']?.toString(),
      ]),
      'locationLabel': _firstNonEmpty([
        readString([
          'locationLabel',
          'currentLocationLabel',
          'selectedLocationLabel',
          'helperLocationLabel',
          'profileLocationLabel',
        ]),
        rawMap['locationLabel']?.toString(),
      ]),
    };
  }

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      final token = await _getToken();
      if (token == null) throw Exception();

      final loc = await _readLocationSnapshot();
      final lat = _dNull(loc['lat']);
      final lng = _dNull(loc['lng']);

      final query = <String, dynamic>{};
      if (lat != null && lng != null) {
        query['helperLat'] = lat.toString();
        query['helperLng'] = lng.toString();
      }

      final res = await http
          .get(_u('/shift-needs/open', query: query), headers: _headers(token))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) {
        throw Exception();
      }

      final data = jsonDecode(res.body);
      final list = List<Map<String, dynamic>>.from(data['items'] ?? []);

      _safeSetState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      _safeSetState(() {
        _err = 'โหลดรายการงานไม่สำเร็จ';
        _loading = false;
      });
    }
  }

  Future<String?> _askPhone() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        bool loading = false;

        return StatefulBuilder(
          builder: (ctx, setSt) {
            Future<void> submit() async {
              final p = _digitsOnly(_phoneCtrl.text);

              if (p.length < 9) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('กรุณากรอกเบอร์โทร')),
                );
                return;
              }

              setSt(() => loading = true);
              Navigator.pop(ctx, p);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ยืนยันเบอร์โทร',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'เบอร์โทร',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: loading ? null : submit,
                    child: const Text('ยืนยัน'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    _phoneCtrl.clear();
    return result;
  }

  Future<void> _apply(String needId) async {
    if (_actingId.isNotEmpty) return;

    try {
      _safeSetState(() => _actingId = needId);

      final token = await _getToken();
      if (token == null) throw Exception();

      final phone = await _askPhone();

      if (phone == null) {
        _safeSetState(() => _actingId = '');
        return;
      }

      final res = await http.post(
        _u('/shift-needs/$needId/apply'),
        headers: _headers(token),
        body: jsonEncode({'phone': phone}),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await showApplySuccessDialog(context);
        await _load();
        return;
      }

      if (res.statusCode == 409) {
        _snack('สมัครแล้ว');
        return;
      }

      throw Exception();
    } catch (_) {
      _snack('สมัครงานไม่สำเร็จ');
    } finally {
      _safeSetState(() => _actingId = '');
    }
  }

  Widget _metaRow(IconData icon, String text, {Color? color}) {
    if (text.trim().isEmpty || text.trim() == '-') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge({
    required String text,
    required Color bg,
    required Color fg,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> m) {
    final id = _s(m['_id']);
    final title =
        _s(m['title']).isNotEmpty ? _s(m['title']) : 'งานว่างจากคลินิก';

    final role = _s(m['role']).isNotEmpty ? _s(m['role']) : _s(m['position']);
    final clinicName = _s(m['clinicName']).isNotEmpty
        ? _s(m['clinicName'])
        : _s(m['clinic_name']);

    final date = _s(m['date']).isNotEmpty ? _s(m['date']) : _s(m['workDate']);
    final start = _s(m['start']).isNotEmpty ? _s(m['start']) : _s(m['startTime']);
    final end = _s(m['end']).isNotEmpty ? _s(m['end']) : _s(m['endTime']);

    final hourlyRate = _d(
      m['hourlyRate'] ??
          m['rate'] ??
          m['salaryPerHour'] ??
          m['payPerHour'] ??
          0,
    );

    final applied = m['_applied'] == true;
    final acting = _actingId == id;
    final urgent = _isUrgent(m);
    final locationDistanceLine = _locationDistanceLine(m);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.purple.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _badge(
                  text: 'เปิดรับอยู่',
                  bg: Colors.purple.shade50,
                  fg: Colors.purple.shade700,
                  icon: Icons.work_outline,
                ),
                if (urgent)
                  _badge(
                    text: 'งานด่วน',
                    bg: Colors.orange.shade50,
                    fg: Colors.orange.shade800,
                    icon: Icons.local_fire_department_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            if (clinicName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                clinicName,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (locationDistanceLine.isNotEmpty)
              _metaRow(
                Icons.location_on_outlined,
                locationDistanceLine,
                color: Colors.purple.shade700,
              ),
            if (role.isNotEmpty) _metaRow(Icons.badge_outlined, role),
            if (date.isNotEmpty)
              _metaRow(Icons.calendar_month_outlined, _formatDateThai(date)),
            if (start.isNotEmpty || end.isNotEmpty)
              _metaRow(Icons.access_time, '$start - $end'),
            if (hourlyRate > 0)
              _metaRow(
                Icons.payments_outlined,
                '${_money(hourlyRate)} บาท/ชม.',
                color: Colors.purple.shade700,
              ),
            const SizedBox(height: 6),
            Text(
              'ค่าจ้างคิดตามเวลาทำงานจริง',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (applied || acting || id.isEmpty) ? null : () => _apply(id),
                icon: acting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(applied ? Icons.check : Icons.send),
                label: Text(
                  applied
                      ? 'สมัครแล้ว'
                      : acting
                          ? 'กำลังสมัคร...'
                          : 'สมัครงานนี้',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.work_outline, size: 70, color: Colors.grey.shade400),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'ยังไม่มีงานว่างตอนนี้',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'เมื่อมีคลินิกเปิดรับงาน จะขึ้นที่หน้านี้',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('รีเฟรช'),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('งานว่างจากคลินิก'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  Card(
                    margin: EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: SizedBox(height: 150),
                  ),
                  Card(
                    margin: EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: SizedBox(height: 150),
                  ),
                  Card(
                    margin: EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: SizedBox(height: 150),
                  ),
                ],
              )
            : _err.isNotEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _err,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('ลองใหม่'),
                        ),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _jobCard(_items[i]),
                      ),
      ),
    );
  }
}