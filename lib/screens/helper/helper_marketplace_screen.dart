import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/helper_marketplace_api.dart';
import 'package:clinic_smart_staff/services/storage_service.dart';

class HelperMarketplaceScreen extends StatefulWidget {
  final Function(Map<String, dynamic>)? onHelperSelected;

  const HelperMarketplaceScreen({
    super.key,
    this.onHelperSelected,
  });

  @override
  State<HelperMarketplaceScreen> createState() =>
      _HelperMarketplaceScreenState();
}

class _HelperMarketplaceScreenState extends State<HelperMarketplaceScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _loadingSearch = false;
  bool _loadingRecommendations = false;

  String _error = '';
  String _clinicId = '';

  List<Map<String, dynamic>> _recommended = [];
  List<Map<String, dynamic>> _searched = [];

  _MarketplaceTab _tab = _MarketplaceTab.recommended;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final storage = StorageService();
      final clinicId = (await storage.getClinicId() ?? '').trim();

      if (!mounted) return;

      setState(() {
        _clinicId = clinicId;
      });

      await _loadRecommendations();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'โหลด Helper Marketplace ไม่สำเร็จ: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadRecommendations() async {
    if (_loadingRecommendations) return;

    if (!mounted) return;
    setState(() {
      _loadingRecommendations = true;
      _error = '';
    });

    try {
      if (_clinicId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _recommended = [];
        });
        return;
      }

      final items = await HelperMarketplaceApi.getRecommendations(
        clinicId: _clinicId,
      );

      if (!mounted) return;
      setState(() {
        _recommended = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'โหลดรายการแนะนำไม่สำเร็จ: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingRecommendations = false;
      });
    }
  }

  Future<void> _searchHelpers() async {
    if (_loadingSearch) return;

    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searched = [];
        _tab = _MarketplaceTab.search;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loadingSearch = true;
      _error = '';
      _tab = _MarketplaceTab.search;
    });

    try {
      final items = await HelperMarketplaceApi.searchHelpers(
        q: q,
        limit: 30,
      );

      if (!mounted) return;
      setState(() {
        _searched = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ค้นหา helper ไม่สำเร็จ: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
      });
    }
  }

  Future<void> _refreshCurrentTab() async {
    if (_tab == _MarketplaceTab.recommended) {
      await _loadRecommendations();
    } else {
      await _searchHelpers();
    }
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  double _d(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  String _displayName(Map<String, dynamic> item) {
    final fullName = _s(item['fullName']);
    if (fullName.isNotEmpty) return fullName;

    final name = _s(item['name']);
    if (name.isNotEmpty) return name;

    final phone = _s(item['phone']);
    if (phone.isNotEmpty) return phone;

    return 'ผู้ช่วย';
  }

  String _translateRole(String raw) {
    final r = _s(raw).toLowerCase();
    if (r.isEmpty) return 'ผู้ช่วย';
    if (r == 'helper') return 'ผู้ช่วย';
    if (r == 'employee') return 'พนักงาน';
    if (r == 'assistant') return 'ผู้ช่วย';
    if (r == 'staff') return 'บุคลากร';
    return _s(raw);
  }

  String _locationLabel(Map<String, dynamic> item) {
    final explicit = _s(
      item['locationLabel'] ??
          item['helperLocationLabel'] ??
          item['profileLocationLabel'],
    );
    if (explicit.isNotEmpty) return explicit;

    final district = _s(item['district'] ?? item['helperDistrict']);
    final province = _s(item['province'] ?? item['helperProvince']);
    final address = _s(item['address'] ?? item['helperAddress']);

    if (district.isNotEmpty && province.isNotEmpty) {
      return '$district, $province';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    if (address.isNotEmpty) return address;

    return '';
  }

  String _distanceText(Map<String, dynamic> item) {
    final explicit = _s(item['distanceText'] ?? item['helperDistanceText']);
    if (explicit.isNotEmpty) return explicit;

    final raw = item['distanceKm'] ?? item['helperDistanceKm'];
    if (raw == null) return '';

    final n = _d(raw);
    if (n <= 0) return '';
    if (n < 10) return '${n.toStringAsFixed(1)} กม.';
    return '${n.round()} กม.';
  }

  String _displaySubtitle(Map<String, dynamic> item) {
    final loc = _locationLabel(item);
    final dist = _distanceText(item);

    if (loc.isNotEmpty && dist.isNotEmpty) {
      return '$loc • $dist จากคลินิก';
    }
    if (dist.isNotEmpty) {
      return '$dist จากคลินิก';
    }
    if (loc.isNotEmpty) {
      return loc;
    }

    final phone = _s(item['phone']);
    if (phone.isNotEmpty) return phone;

    return 'ยังไม่มีข้อมูลพื้นที่';
  }

  String _scoreText(Map<String, dynamic> item) {
    final score = item['trustScore'];
    if (score == null) return '80';

    final n = _d(score);
    if (n <= 0) return '80';
    return n.toStringAsFixed(0);
  }

  String _levelLabel(Map<String, dynamic> item) {
    final levelLabel = _s(item['levelLabel']);
    if (levelLabel.isNotEmpty) return levelLabel;

    final level = _s(item['level']);
    if (level.isNotEmpty) return level;

    final score = _d(item['trustScore']);
    if (score >= 90) return 'ยอดเยี่ยม';
    if (score >= 80) return 'ดี';
    if (score >= 60) return 'ปกติ';
    return 'ยังไม่มีข้อมูล';
  }

  List<String> _stringList(dynamic v) {
    if (v is List) {
      return v.map((e) => _s(e)).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  Map<String, dynamic> _stats(Map<String, dynamic> item) {
    final raw = item['stats'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  bool _canUseItem(Map<String, dynamic> item) {
    final userId = _s(item['userId']);
    final staffId = _s(item['staffId']);
    return userId.isNotEmpty || staffId.isNotEmpty;
  }

  Color _scoreColor(BuildContext context, Map<String, dynamic> item) {
    final score = _d(item['trustScore']);

    if (score >= 90) return Colors.green.shade700;
    if (score >= 80) return Colors.blue.shade700;
    if (score >= 60) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  void _selectHelper(Map<String, dynamic> item) {
    if (widget.onHelperSelected != null) {
      widget.onHelperSelected!(item);
      return;
    }

    Navigator.pop(context, item);
  }

  void _openHelperDetails(Map<String, dynamic> item) {
    final stats = _stats(item);
    final badges = _stringList(item['badges']);
    final flags = _stringList(item['flags']);
    final scoreColor = _scoreColor(context, item);

    final roleText = _translateRole(item['role']);
    final phoneText = _s(item['phone']);
    final locationText = _locationLabel(item);
    final distanceText = _distanceText(item);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        child: Text(
                          _displayName(item).trim().isNotEmpty
                              ? _displayName(item)
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase()
                              : '?',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName(item),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _displaySubtitle(item),
                              style: TextStyle(
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scoreColor.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _scoreText(item),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: scoreColor,
                              ),
                            ),
                            Text(
                              'Score',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scoreColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildDetailRow('ระดับ', _levelLabel(item)),
                  _buildDetailRow(
                    'เบอร์โทร',
                    phoneText.isNotEmpty ? phoneText : '-',
                  ),
                  _buildDetailRow('บทบาท', roleText),
                  _buildDetailRow(
                    'พื้นที่',
                    locationText.isNotEmpty ? locationText : 'ยังไม่มีข้อมูลพื้นที่',
                  ),
                  _buildDetailRow(
                    'ระยะจากคลินิก',
                    distanceText.isNotEmpty ? distanceText : 'ยังไม่มีข้อมูลระยะทาง',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'สถิติการทำงาน',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStatPill('งานทั้งหมด', '${_i(stats['totalShifts'])}'),
                      _buildStatPill('สำเร็จ', '${_i(stats['completed'])}'),
                      _buildStatPill('สาย', '${_i(stats['late'])}'),
                      _buildStatPill('No-show', '${_i(stats['noShow'])}'),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Badge',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: badges
                          .map(
                            (e) => _buildTag(
                              e,
                              background: Colors.blue.shade50,
                              foreground: Colors.blue.shade800,
                              border: Colors.blue.shade200,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (flags.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'หมายเหตุ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: flags
                          .map(
                            (e) => _buildTag(
                              e,
                              background: Colors.orange.shade50,
                              foreground: Colors.orange.shade900,
                              border: Colors.orange.shade200,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _selectHelper(item);
                      },
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('เลือกผู้ช่วยคนนี้'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(
    String text, {
    required Color background,
    required Color foreground,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }

  Widget _buildHelperCard(Map<String, dynamic> item) {
    final stats = _stats(item);
    final levelText = _levelLabel(item);
    final trustScore = _scoreText(item);
    final scoreColor = _scoreColor(context, item);
    final roleText = _translateRole(item['role']);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(
                    _displayName(item).trim().isNotEmpty
                        ? _displayName(item).trim().characters.first.toUpperCase()
                        : '?',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName(item),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _displaySubtitle(item),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        trustScore,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: scoreColor,
                        ),
                      ),
                      Text(
                        'Score',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'ระดับ: $levelText',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'บทบาท: $roleText',
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatPill('งานทั้งหมด', '${_i(stats['totalShifts'])}'),
                _buildStatPill('สำเร็จ', '${_i(stats['completed'])}'),
                _buildStatPill('สาย', '${_i(stats['late'])}'),
                _buildStatPill('No-show', '${_i(stats['noShow'])}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _canUseItem(item)
                        ? () => _openHelperDetails(item)
                        : null,
                    icon: const Icon(Icons.visibility),
                    label: const Text('ดูรายละเอียด'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _canUseItem(item)
                        ? () => _selectHelper(item)
                        : null,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('เลือกผู้ช่วย'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBody() {
    final items =
        _tab == _MarketplaceTab.recommended ? _recommended : _searched;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade700),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Center(child: Text('ยังไม่มีข้อมูล')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCurrentTab,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildHelperCard(items[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Helper Marketplace'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchHelpers(),
                    decoration: InputDecoration(
                      hintText: 'ค้นหาผู้ช่วยด้วยชื่อ เบอร์ หรือรหัส',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loadingSearch ? null : _searchHelpers,
                  child: _loadingSearch
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ค้นหา'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('แนะนำ'),
                    selected: _tab == _MarketplaceTab.recommended,
                    onSelected: (_) {
                      setState(() {
                        _tab = _MarketplaceTab.recommended;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('ค้นหา'),
                    selected: _tab == _MarketplaceTab.search,
                    onSelected: (_) {
                      setState(() {
                        _tab = _MarketplaceTab.search;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _error,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

enum _MarketplaceTab {
  recommended,
  search,
}