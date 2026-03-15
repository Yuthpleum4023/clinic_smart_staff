import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';
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

  double _d(dynamic v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fallback;
  }

  String _money(double n) {
    if (n <= 0) return '0';
    if (n == n.roundToDouble()) return n.toStringAsFixed(0);
    return n.toStringAsFixed(2);
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
    if (km < 1) return '${(km * 1000).round()} เมตร';
    if (km < 10) return '${km.toStringAsFixed(1)} กม.';
    return '${km.round()} กม.';
  }

  String _locationText(Map<String, dynamic> m) {
    final district = _s(
      m['clinicDistrict'] ?? m['district'] ?? m['amphoe'],
    );
    final province = _s(
      m['clinicProvince'] ?? m['province'] ?? m['changwat'],
    );
    final label = _s(
      m['clinicLocationLabel'] ?? m['locationLabel'] ?? m['label'],
    );

    final joined = [district, province]
        .where((e) => e.trim().isNotEmpty)
        .join(', ');

    if (joined.isNotEmpty) return joined;
    if (label.isNotEmpty) return label;
    return '';
  }

  String _locationDistanceLine(Map<String, dynamic> m) {
    final location = _locationText(m);
    final dist = _distanceText(m);

    if (location.isNotEmpty && dist.isNotEmpty) {
      return '📍 $location • ห่างจากคุณ $dist';
    }
    if (location.isNotEmpty) {
      return '📍 $location';
    }
    if (dist.isNotEmpty) {
      return '📍 ห่างจากคุณ $dist';
    }
    return '';
  }

  String _clinicPhone(Map<String, dynamic> m) {
    return _s(
      m['clinicPhone'] ??
          m['phone'] ??
          m['contactPhone'] ??
          m['clinic_phone'],
    );
  }

  double _hourlyRate(Map<String, dynamic> m) {
    return _d(
      m['hourlyRate'] ??
          m['rate'] ??
          m['salaryPerHour'] ??
          m['payPerHour'] ??
          0,
    );
  }

  String _timeLine(Map<String, dynamic> m) {
    final start = _s(m['start'] ?? m['startTime']);
    final end = _s(m['end'] ?? m['endTime']);

    if (start.isNotEmpty && end.isNotEmpty) {
      return 'เวลา $start - $end';
    }
    if (start.isNotEmpty) return 'เริ่ม $start';
    if (end.isNotEmpty) return 'ถึง $end';
    return '';
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

    return uri.replace(queryParameters: qp);
  }

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _err = '';
    });

    try {
      final token = await _getToken();
      if (token == null) throw Exception('missing token');

      final helperLoc = await SettingService.loadHelperLocation();

      final query = <String, dynamic>{};
      if (helperLoc != null) {
        query['helperLat'] = helperLoc.lat.toString();
        query['helperLng'] = helperLoc.lng.toString();
      }

      final res = await http
          .get(_u('/shift-needs/open', query: query), headers: _headers(token))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) {
        throw Exception('load failed ${res.statusCode}');
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
              final p = _phoneCtrl.text.trim();

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
      if (token == null) throw Exception('missing token');

      final phone = await _askPhone();
      if (phone == null) {
        _safeSetState(() => _actingId = '');
        return;
      }

      final helperLoc = await SettingService.loadHelperLocation();

      final body = <String, dynamic>{
        'phone': phone,
      };

      if (helperLoc != null) {
        body['lat'] = helperLoc.lat;
        body['lng'] = helperLoc.lng;
        body['district'] = helperLoc.district;
        body['province'] = helperLoc.province;
        body['address'] = helperLoc.address;
        body['label'] = helperLoc.label;
      }

      final res = await http.post(
        _u('/shift-needs/$needId/apply'),
        headers: _headers(token),
        body: jsonEncode(body),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await showApplySuccessDialog(context);
        await _load();
        return;
      }

      String msg = 'สมัครงานไม่สำเร็จ';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['message'] != null) {
          msg = decoded['message'].toString();
        } else if (decoded is Map && decoded['error'] != null) {
          msg = decoded['error'].toString();
        }
      } catch (_) {}

      throw Exception(msg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      _safeSetState(() => _actingId = '');
    }
  }

  Future<void> _callClinic(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;

    final uri = Uri.parse('tel:$clean');

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรออกได้')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดหน้าจอโทรออกได้')),
      );
    }
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

  Widget _jobCard(Map<String, dynamic> m) {
    final id = _s(m['_id']);
    final title =
        _s(m['title']).isNotEmpty ? _s(m['title']) : 'งานว่างจากคลินิก';

    final clinicName = _s(m['clinicName']);
    final clinicPhone = _clinicPhone(m);
    final hourlyRate = _hourlyRate(m);
    final distanceLine = _locationDistanceLine(m);
    final timeLine = _timeLine(m);

    final applied = m['_applied'] == true;
    final acting = _actingId == id;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.purple.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            if (clinicName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  clinicName,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            if (distanceLine.isNotEmpty)
              _metaRow(
                Icons.location_on_outlined,
                distanceLine,
                color: Colors.purple.shade700,
                fontWeight: FontWeight.w800,
              ),
            if (timeLine.isNotEmpty)
              _metaRow(
                Icons.access_time,
                timeLine,
                color: Colors.deepPurple.shade700,
                fontWeight: FontWeight.w700,
              ),
            if (hourlyRate > 0)
              _metaRow(
                Icons.payments_outlined,
                'ค่าจ้าง ${_money(hourlyRate)} บาท/ชม.',
                color: Colors.green.shade700,
                fontWeight: FontWeight.w800,
              ),
            if (clinicPhone.isNotEmpty)
              _metaRow(
                Icons.phone_outlined,
                'โทร $clinicPhone',
                color: Colors.blueGrey.shade700,
              ),
            const SizedBox(height: 16),
            if (clinicPhone.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _callClinic(clinicPhone),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('โทรถามก่อน'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (id.isEmpty || acting || applied)
                    ? null
                    : () => _apply(id),
                icon: acting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
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
      children: const [
        SizedBox(height: 140),
        Center(
          child: Text(
            'ยังไม่มีงานว่าง',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _errorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 140),
        Center(
          child: Text(
            _err,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
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
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _err.isNotEmpty
                ? _errorState()
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