import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/api_client.dart';
import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/api/trust_score_api.dart';

class TrustScoreLookupScreen extends StatefulWidget {
  const TrustScoreLookupScreen({super.key});

  @override
  State<TrustScoreLookupScreen> createState() => _TrustScoreLookupScreenState();
}

class _TrustScoreLookupScreenState extends State<TrustScoreLookupScreen> {
  final _inputCtrl = TextEditingController();

  bool _loading = false;
  Map<String, dynamic>? _score;

  static ApiClient get _authClient =>
      ApiClient(baseUrl: ApiConfig.authBaseUrl);

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------------- helpers ----------------
  String _s(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  bool _looksLikePhone(String s) {
    final d = _digitsOnly(s);
    return d.length >= 9 && d.length <= 12;
  }

  bool _isStaffId(String s) {
    final v = _s(s).toLowerCase();
    return v.startsWith('stf_') && v.length >= 6;
  }

  List<String> _splitTokens(String input) {
    return input
        .split('/')
        .expand((x) => x.split(RegExp(r'\s+')))
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
  }

  int _toInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString().trim()) ?? fallback;
  }

  Map<String, dynamic> _scorePayload(dynamic decoded) {
    final root = _asMap(decoded);
    final inner = root['score'];
    if (inner is Map) return _asMap(inner);
    return root;
  }

  dynamic _getStat(String key) {
    final s = _score ?? {};
    if (s.containsKey(key)) return s[key];

    final stats = s['stats'];
    if (stats is Map) {
      final m = _asMap(stats);
      return m[key];
    }
    return null;
  }

  String _str(dynamic v, {String fallback = '-'}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  // ---------------- level logic ----------------
  String _levelLabelFromScore(int score) {
    if (score >= 90) return 'ยอดเยี่ยม';
    if (score >= 75) return 'ดีมาก';
    if (score >= 60) return 'ปกติ';
    return 'ควรระวัง';
  }

  String _levelCodeFromScore(int score) {
    if (score >= 90) return 'excellent';
    if (score >= 75) return 'good';
    if (score >= 60) return 'normal';
    return 'risk';
  }

  // ---------------- AUTH search ----------------
  Future<List<Map<String, dynamic>>> _searchStaff(String q) async {
    final query = _s(q);
    if (query.isEmpty) return [];

    final path =
        '${ApiConfig.staffSearch}?q=${Uri.encodeComponent(query)}&limit=20';

    final decoded = await _authClient.get(path, auth: true);

    final root = _asMap(decoded);
    dynamic items = root['items'];

    if (items is! List) items = root['results'];
    if (items is! List) items = root['data'];
    if (items is! List) return [];

    final out = <Map<String, dynamic>>[];

    for (final x in items) {
      if (x is Map) {
        final m = Map<String, dynamic>.from(x);
        final sid = _s(m['staffId']);
        if (sid.isEmpty) continue;

        out.add({
          'staffId': sid,
          'fullName': _s(m['fullName'] ?? m['name']),
          'phone': _s(m['phone']),
        });
      }
    }
    return out;
  }

  Future<Map<String, dynamic>?> _pickCandidate(
    List<Map<String, dynamic>> items,
  ) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'เลือกผู้ช่วย',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            ...items.map((m) {
              final name = _s(m['fullName']);
              final phone = _s(m['phone']);

              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(name.isEmpty ? 'ผู้ช่วย' : name),
                subtitle: Text(
                  phone.isEmpty ? 'ยังไม่มีข้อมูลเบอร์โทร' : 'โทร: $phone',
                ),
                onTap: () => Navigator.pop(ctx, m),
              );
            }),
          ],
        );
      },
    );
  }

  // ---------------- MAIN FLOW ----------------
  Future<void> _fetch() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) {
      _snack('กรุณากรอกชื่อหรือเบอร์โทร');
      return;
    }

    setState(() {
      _loading = true;
      _score = null;
    });

    try {
      String staffId = '';

      if (_isStaffId(input)) {
        staffId = input;
      } else {
        final tokens = _splitTokens(input);

        String phoneDigits = '';
        for (final t in tokens) {
          if (phoneDigits.isEmpty && _looksLikePhone(t)) {
            phoneDigits = _digitsOnly(t);
          }
        }

        final q = phoneDigits.isNotEmpty ? phoneDigits : input;

        final candidates = await _searchStaff(q);

        if (candidates.isEmpty) {
          _snack('ไม่พบผู้ช่วยที่ตรงกับข้อมูล');
          return;
        }

        if (candidates.length == 1) {
          staffId = _s(candidates.first['staffId']);
        } else {
          final chosen = await _pickCandidate(candidates);
          if (chosen == null) return;
          staffId = _s(chosen['staffId']);
        }
      }

      if (staffId.isEmpty) {
        _snack('ไม่สามารถระบุผู้ช่วยได้');
        return;
      }

      final raw = await TrustScoreApi.getStaffScore(
        staffId: staffId,
        auth: true,
      );

      final payload = _scorePayload(raw);

      if (!mounted) return;
      setState(() => _score = payload);
    } catch (_) {
      _snack('โหลดคะแนนไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final query = _inputCtrl.text.trim();
    final canSearch = !_loading && query.isNotEmpty;

    final trustScoreInt = _toInt(_getStat('trustScore'));

    final backendLevel = _s(_score?['level']);
    final backendLabel = _s(_score?['levelLabel']);

    final levelCode = backendLevel.isNotEmpty
        ? backendLevel
        : _levelCodeFromScore(trustScoreInt);

    final levelLabel = backendLabel.isNotEmpty
        ? backendLabel
        : _levelLabelFromScore(trustScoreInt);

    Color levelColor() {
      switch (levelCode) {
        case 'excellent':
          return Colors.green;
        case 'good':
          return cs.primary;
        case 'normal':
          return Colors.orange;
        case 'risk':
          return Colors.red;
        default:
          return cs.primary;
      }
    }

    Widget levelBadge() {
      final c = levelColor();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          levelLabel,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    Widget stat(String label, dynamic value) {
      return Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _str(value),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('TrustScore ผู้ช่วย')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _inputCtrl,
              decoration: const InputDecoration(
                labelText: 'ค้นหาผู้ช่วย',
                hintText: 'ชื่อ หรือ เบอร์โทร',
                border: OutlineInputBorder(),
              ),

              // ✅ สำคัญมาก: ให้ปุ่ม Search enable/disable ได้ทันที
              onChanged: (_) {
                // ถ้ามีผลเก่าอยู่ แล้วเริ่มพิมพ์ใหม่ → เคลียร์ผลเก่า
                if (_score != null) _score = null;
                setState(() {});
              },

              // ✅ แก้ให้เรียกจริง
              onSubmitted: (_) {
                if (canSearch) _fetch();
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: canSearch ? _fetch : null,
              icon: const Icon(Icons.search),
              label: const Text('ค้นหา'),
            ),
            const SizedBox(height: 14),

            if (_loading)
              const Center(child: CircularProgressIndicator()),

            if (!_loading && _score == null)
              Text(
                'ค้นหาผู้ช่วยเพื่อดูคะแนนความน่าเชื่อถือ',
                style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
              ),

            if (_score != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _s(_score?['fullName']).isEmpty
                            ? 'ผลการประเมิน'
                            : _s(_score?['fullName']),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'TrustScore: $trustScoreInt',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 10),
                          levelBadge(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      stat('จำนวนงานทั้งหมด', _getStat('totalShifts')),
                      stat('ทำงานสำเร็จ', _getStat('completed')),
                      stat('มาสาย', _getStat('late')),
                      stat('ยกเลิกกระชั้นชิด', _getStat('cancelledEarly')),
                      stat('ไม่มาตามนัด', _getStat('noShow')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}