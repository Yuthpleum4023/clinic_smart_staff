import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/trust_score_api.dart';

class TrustScoreLookupScreen extends StatefulWidget {
  final Map<String, dynamic>? initialHelper;
  final String initialStaffId;
  final String initialQuery;

  const TrustScoreLookupScreen({
    super.key,
    this.initialHelper,
    this.initialStaffId = '',
    this.initialQuery = '',
  });

  @override
  State<TrustScoreLookupScreen> createState() => _TrustScoreLookupScreenState();
}

class _TrustScoreLookupScreenState extends State<TrustScoreLookupScreen> {
  final _inputCtrl = TextEditingController();

  bool _loading = false;
  Map<String, dynamic>? _score;
  List<Map<String, dynamic>> _searchResults = [];
  String _selectedStaffId = '';

  @override
  void initState() {
    super.initState();
    _bootstrapInitialLookup();
  }

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
      if (m.containsKey(key)) return m[key];

      // fallback alias
      if (key == 'cancelledEarly' && m.containsKey('cancelled')) {
        return m['cancelled'];
      }
    }

    return null;
  }

  String _str(dynamic v, {String fallback = '-'}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _displayHelperName(Map<String, dynamic> item) {
    final fullName = _s(item['fullName']);
    if (fullName.isNotEmpty) return fullName;

    final name = _s(item['name']);
    if (name.isNotEmpty) return name;

    final phone = _s(item['phone']);
    if (phone.isNotEmpty) return phone;

    final userId = _s(item['userId']);
    if (userId.isNotEmpty) return userId;

    final staffId = _s(item['staffId']);
    if (staffId.isNotEmpty) return staffId;

    return 'ผู้ช่วย';
  }

  String _displaySubtitle(Map<String, dynamic> item) {
    final phone = _s(item['phone']);
    final role = _s(item['role']);
    final levelLabel = _s(item['levelLabel']);

    final parts = <String>[
      if (phone.isNotEmpty) 'โทร $phone',
      if (role.isNotEmpty) role,
      if (levelLabel.isNotEmpty) levelLabel,
    ];

    if (parts.isEmpty) return 'แตะเพื่อดูคะแนนความน่าเชื่อถือ';
    return parts.join(' • ');
  }

  Future<void> _bootstrapInitialLookup() async {
    final helper = widget.initialHelper;
    final initialStaffId = _s(widget.initialStaffId);
    final initialQuery = _s(widget.initialQuery);

    String prefill = '';

    if (helper != null && helper.isNotEmpty) {
      final helperMap = _asMap(helper);

      prefill = _displayHelperName(helperMap);
      if (prefill.isEmpty) {
        prefill = _s(helperMap['phone']);
      }

      final helperStaffId = _s(helperMap['staffId']);
      if (helperStaffId.isNotEmpty) {
        _inputCtrl.text = prefill.isNotEmpty ? prefill : helperStaffId;
        await _fetchByStaffId(helperStaffId);
        return;
      }
    }

    if (initialStaffId.isNotEmpty) {
      _inputCtrl.text = initialStaffId;
      await _fetchByStaffId(initialStaffId);
      return;
    }

    if (initialQuery.isNotEmpty) {
      _inputCtrl.text = initialQuery;
    }
  }

  // ---------------- level logic ----------------
  String _levelLabelFromScore(int score) {
    if (score >= 90) return 'ยอดเยี่ยม';
    if (score >= 80) return 'ดี';
    if (score >= 60) return 'ปกติ';
    return 'เสี่ยง';
  }

  String _levelCodeFromScore(int score) {
    if (score >= 90) return 'excellent';
    if (score >= 80) return 'good';
    if (score >= 60) return 'normal';
    return 'risk';
  }

  // ---------------- helper search ----------------
  Future<List<Map<String, dynamic>>> _searchStaff(String q) async {
    final query = _s(q);
    if (query.isEmpty) return [];

    final items = await TrustScoreApi.searchStaff(
      q: query,
      limit: 20,
      auth: true,
    );

    final out = <Map<String, dynamic>>[];

    for (final raw in items) {
      final m = _asMap(raw);
      final sid = _s(m['staffId']);

      // อนุญาตให้โชว์ได้ถ้ามี staffId หรือ userId
      if (sid.isEmpty && _s(m['userId']).isEmpty) continue;

      out.add({
        'staffId': sid,
        'userId': _s(m['userId']),
        'fullName': _s(m['fullName']),
        'name': _s(m['name']),
        'phone': _s(m['phone']),
        'role': _s(m['role']),
        'trustScore': m['trustScore'],
        'level': _s(m['level']),
        'levelLabel': _s(m['levelLabel']),
      });
    }

    return out;
  }

  // ---------------- MAIN FLOW ----------------
  Future<void> _fetchByStaffId(String staffId) async {
    final sid = _s(staffId);
    if (sid.isEmpty) {
      _snack('ไม่สามารถระบุผู้ช่วยได้');
      return;
    }

    setState(() {
      _loading = true;
      _score = null;
      _selectedStaffId = sid;
    });

    try {
      final raw = await TrustScoreApi.getStaffScore(
        staffId: sid,
        auth: true,
      );

      final payload = _scorePayload(raw);

      if (!mounted) return;
      setState(() => _score = payload);
    } catch (e) {
      _snack('โหลดคะแนนไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _fetch() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty) {
      _snack('กรุณากรอกชื่อ เบอร์โทร หรือ staffId');
      return;
    }

    setState(() {
      _loading = true;
      _score = null;
      _searchResults = [];
      _selectedStaffId = '';
    });

    try {
      if (_isStaffId(input)) {
        await _fetchByStaffId(input);
        return;
      }

      final tokens = _splitTokens(input);

      String phoneDigits = '';
      for (final t in tokens) {
        if (phoneDigits.isEmpty && _looksLikePhone(t)) {
          phoneDigits = _digitsOnly(t);
        }
      }

      final q = phoneDigits.isNotEmpty ? phoneDigits : input;
      final candidates = await _searchStaff(q);

      if (!mounted) return;

      if (candidates.isEmpty) {
        setState(() {
          _searchResults = [];
        });
        _snack('ไม่พบผู้ช่วยที่ตรงกับข้อมูล');
        return;
      }

      setState(() {
        _searchResults = candidates;
      });

      if (candidates.length == 1) {
        final sid = _s(candidates.first['staffId']);
        if (sid.isNotEmpty) {
          await _fetchByStaffId(sid);
        }
      }
    } catch (e) {
      _snack('ค้นหาไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Color _scoreColor(int score, ColorScheme cs) {
    if (score >= 90) return Colors.green;
    if (score >= 80) return cs.primary;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  Widget _buildResultCard(Map<String, dynamic> item, ColorScheme cs) {
    final name = _displayHelperName(item);
    final subtitle = _displaySubtitle(item);
    final score = _toInt(item['trustScore'], fallback: 0);
    final scoreColor = _scoreColor(score, cs);
    final sid = _s(item['staffId']);
    final selected = sid.isNotEmpty && sid == _selectedStaffId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: selected ? 2 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: sid.isEmpty ? null : () => _fetchByStaffId(sid),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '$score',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: scoreColor,
                      ),
                    ),
                    Text(
                      'Score',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard(ColorScheme cs) {
    if (_score == null) return const SizedBox.shrink();

    final trustScoreInt = _toInt(_score?['trustScore']);
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              _str(value),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 10),
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
            if (_s(_score?['phone']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'โทร: ${_s(_score?['phone'])}',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.65),
                ),
              ),
            ],
            const SizedBox(height: 10),
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
            const SizedBox(height: 12),
            stat('จำนวนงานทั้งหมด', _getStat('totalShifts')),
            stat('ทำงานสำเร็จ', _getStat('completed')),
            stat('มาสาย', _getStat('late')),
            stat('ยกเลิกกระชั้นชิด', _getStat('cancelledEarly')),
            stat('ไม่มาตามนัด', _getStat('noShow')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final query = _inputCtrl.text.trim();
    final canSearch = !_loading && query.isNotEmpty;

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
                hintText: 'ชื่อ หรือ เบอร์โทร หรือ staffId',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                setState(() {
                  _score = null;
                  _selectedStaffId = '';
                });
              },
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

            if (_loading) const Center(child: CircularProgressIndicator()),

            if (!_loading && _score == null && _searchResults.isEmpty)
              Text(
                'ค้นหาผู้ช่วยเพื่อดูคะแนนความน่าเชื่อถือ',
                style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
              ),

            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'ผลการค้นหา',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ..._searchResults.map((item) => _buildResultCard(item, cs)),
            ],

            _buildScoreCard(cs),
          ],
        ),
      ),
    );
  }
}