import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/helper_marketplace_api.dart';
import 'package:clinic_smart_staff/services/helper_recommendation.dart';
import 'package:clinic_smart_staff/services/location_engine.dart';
import 'package:clinic_smart_staff/services/location_manager.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';
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
  final FocusNode _searchFocusNode = FocusNode();

  bool _loading = true;
  bool _loadingSearch = false;
  bool _loadingRecommendations = false;

  String _error = '';
  String _clinicId = '';

  AppLocation? _clinicLocation;
  bool _usingGpsFallback = false;

  List<Map<String, dynamic>> _recommended = [];
  List<Map<String, dynamic>> _searched = [];

  final Map<String, HelperRecommendationResult> _recommendedRankMap = {};
  final Map<String, HelperRecommendationResult> _searchedRankMap = {};

  _MarketplaceTab _tab = _MarketplaceTab.recommended;
  HelperSortMode _sortMode = HelperSortMode.recommended;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  bool _hasUsableLocation(AppLocation? loc) {
    if (loc == null) return false;
    return loc.lat != 0 && loc.lng != 0;
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<AppLocation?> _ensureClinicLocation() async {
    final local = await SettingService.loadClinicLocation();
    if (_hasUsableLocation(local)) {
      debugPrint(
        '[HelperMarketplace] clinic location source=local '
        'lat=${local!.lat} lng=${local.lng}',
      );
      _usingGpsFallback = false;
      return local;
    }

    final backend = await LocationManager.loadClinicLocationSmart(
      allowGpsFallback: false,
    );
    if (_hasUsableLocation(backend)) {
      debugPrint(
        '[HelperMarketplace] clinic location source=backend '
        'lat=${backend!.lat} lng=${backend.lng}',
      );
      _usingGpsFallback = false;
      return backend;
    }

    final gps = await LocationManager.loadClinicLocationSmart(
      allowGpsFallback: true,
    );
    if (_hasUsableLocation(gps)) {
      debugPrint(
        '[HelperMarketplace] clinic location source=gps_fallback '
        'lat=${gps!.lat} lng=${gps.lng}',
      );
      _usingGpsFallback = true;
      return gps;
    }

    debugPrint('[HelperMarketplace] clinic location source=none');
    _usingGpsFallback = false;
    return null;
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
      final clinicLocation = await _ensureClinicLocation();

      debugPrint(
        '[HelperMarketplace] bootstrap clinicId=$clinicId '
        'clinicLat=${clinicLocation?.lat} clinicLng=${clinicLocation?.lng} '
        'usingGpsFallback=$_usingGpsFallback',
      );

      if (!mounted) return;

      setState(() {
        _clinicId = clinicId;
        _clinicLocation = clinicLocation;
      });

      await _loadRecommendations();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'โหลดหน้าค้นหาผู้ช่วยไม่สำเร็จ: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  String _rankKey(Map<String, dynamic> item) {
    final userId = _s(item['userId']);
    final staffId = _s(item['staffId']);
    return userId.isNotEmpty ? 'u:$userId' : 's:$staffId';
  }

  List<Map<String, dynamic>> _sortItems(
    List<Map<String, dynamic>> items,
    Map<String, HelperRecommendationResult> targetMap,
  ) {
    final ranked = HelperRecommendationEngine.rankHelpers(
      helpers: items,
      clinicLocation: _clinicLocation,
      sortMode: _sortMode,
    );

    targetMap.clear();
    for (final r in ranked) {
      targetMap[_rankKey(r.helper)] = r;
    }

    return ranked.map((e) => e.helper).toList();
  }

  HelperRecommendationResult? _rankOf(Map<String, dynamic> item) {
    final key = _rankKey(item);
    if (_tab == _MarketplaceTab.recommended) {
      return _recommendedRankMap[key];
    }
    return _searchedRankMap[key];
  }

  void _debugFirstItem(String label, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      debugPrint('[HelperMarketplace] $label -> no items');
      return;
    }

    final first = items.first;
    debugPrint(
      '[HelperMarketplace] $label -> count=${items.length} '
      'name=${_displayName(first)} '
      'lat=${first['lat']} lng=${first['lng']} '
      'district=${first['district']} province=${first['province']} '
      'areaText=${first['areaText']} '
      'distanceKm=${first['distanceKm']} '
      'distanceText=${first['distanceText']} '
      'nearClinic=${first['nearClinic']}',
    );
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
          _recommendedRankMap.clear();
        });
        return;
      }

      debugPrint(
        '[HelperMarketplace] loadRecommendations clinicId=$_clinicId '
        'clinicLat=${_clinicLocation?.lat} clinicLng=${_clinicLocation?.lng}',
      );

      final items = await HelperMarketplaceApi.getRecommendations(
        clinicId: _clinicId,
        clinicLat: _clinicLocation?.lat,
        clinicLng: _clinicLocation?.lng,
      );

      _debugFirstItem('recommendations response', items);

      if (!mounted) return;
      setState(() {
        _recommended = _sortItems(items, _recommendedRankMap);
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

    _dismissKeyboard();

    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searched = [];
        _searchedRankMap.clear();
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
      debugPrint(
        '[HelperMarketplace] searchHelpers q="$q" '
        'clinicLat=${_clinicLocation?.lat} clinicLng=${_clinicLocation?.lng}',
      );

      final items = await HelperMarketplaceApi.searchHelpers(
        q: q,
        limit: 30,
        clinicLat: _clinicLocation?.lat,
        clinicLng: _clinicLocation?.lng,
      );

      _debugFirstItem('search response', items);

      if (!mounted) return;
      setState(() {
        _searched = _sortItems(items, _searchedRankMap);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ค้นหาผู้ช่วยไม่สำเร็จ: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
      });
    }
  }

  Future<void> _refreshCurrentTab() async {
    _dismissKeyboard();

    final clinicLocation = await _ensureClinicLocation();

    if (!mounted) return;

    setState(() {
      _clinicLocation = clinicLocation;
    });

    debugPrint(
      '[HelperMarketplace] refresh clinicLat=${_clinicLocation?.lat} '
      'clinicLng=${_clinicLocation?.lng} tab=$_tab '
      'usingGpsFallback=$_usingGpsFallback',
    );

    if (_tab == _MarketplaceTab.recommended) {
      await _loadRecommendations();
    } else {
      await _searchHelpers();
    }
  }

  void _changeSortMode(HelperSortMode mode) {
    if (_sortMode == mode) return;

    setState(() {
      _sortMode = mode;
      _recommended = _sortItems(_recommended, _recommendedRankMap);
      _searched = _sortItems(_searched, _searchedRankMap);
    });
  }

  String _sortLabel(HelperSortMode mode) {
    switch (mode) {
      case HelperSortMode.recommended:
        return 'แนะนำ';
      case HelperSortMode.trustScore:
        return 'คะแนน';
      case HelperSortMode.distance:
        return 'ใกล้คลินิก';
      case HelperSortMode.experience:
        return 'ประสบการณ์';
    }
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
    return LocationEngine.resolveLocationLabelForItem(item);
  }

  String _distanceText(Map<String, dynamic> item) {
    return LocationEngine.resolveDistanceTextForItem(item, _clinicLocation);
  }

  String _nearbyLabel(Map<String, dynamic> item) {
    return LocationEngine.resolveNearbyLabelForItem(item, _clinicLocation);
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

  Color _scoreColor(Map<String, dynamic> item) {
    final score = _d(item['trustScore']);

    if (score >= 90) return Colors.green.shade700;
    if (score >= 80) return Colors.blue.shade700;
    if (score >= 60) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  List<String> _recommendationBadges(Map<String, dynamic> item) {
    final result = _rankOf(item);
    if (result == null) return [];

    final out = <String>[];

    if (_sortMode == HelperSortMode.recommended && result.finalScore >= 85) {
      out.add('แนะนำ');
    }
    if (result.nearbyLabel.trim().isNotEmpty) {
      out.add(result.nearbyLabel.trim());
    }
    if (result.trustScore >= 90) {
      out.add('คะแนนดีมาก');
    } else if (result.trustScore >= 80) {
      out.add('คะแนนดี');
    }
    if (result.totalShifts >= 20) {
      out.add('ประสบการณ์สูง');
    }

    return out;
  }

  void _selectHelper(Map<String, dynamic> item) {
    _dismissKeyboard();

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
    final scoreColor = _scoreColor(item);
    final rank = _rankOf(item);

    final roleText = _translateRole(item['role']);
    final phoneText = _s(item['phone']);
    final locationText = _locationLabel(item);
    final distanceText = _distanceText(item);
    final nearbyText = _nearbyLabel(item);

    _dismissKeyboard();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: GestureDetector(
              onTap: () => FocusScope.of(sheetContext).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
                            color: scoreColor.withAlpha(26),
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
                                'คะแนน',
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
                    if (nearbyText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildTag(
                        nearbyText,
                        background: Colors.green.shade50,
                        foreground: Colors.green.shade800,
                        border: Colors.green.shade200,
                      ),
                    ],
                    if (rank != null && rank.reasons.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'เหตุผลที่แนะนำ',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: rank.reasons
                            .map(
                              (e) => _buildTag(
                                e,
                                background: Colors.purple.shade50,
                                foreground: Colors.purple.shade800,
                                border: Colors.purple.shade200,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (rank != null && rank.warnings.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'ข้อสังเกต',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: rank.warnings
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
                    const SizedBox(height: 18),
                    _buildDetailRow('ระดับ', _levelLabel(item)),
                    if (rank != null)
                      _buildDetailRow(
                        'คะแนนแนะนำ',
                        rank.finalScore.toStringAsFixed(1),
                      ),
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
                      distanceText.isNotEmpty
                          ? distanceText
                          : 'ยังไม่มีข้อมูลระยะทาง',
                    ),
                    if (rank != null)
                      _buildDetailRow(
                        'ประสบการณ์รวม',
                        '${rank.totalShifts} งาน',
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
                        _buildStatPill('มาสาย', '${_i(stats['late'])}'),
                        _buildStatPill('ไม่มาตามนัด', '${_i(stats['noShow'])}'),
                      ],
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'จุดเด่น',
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
                          Navigator.of(sheetContext).pop();
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
            width: 100,
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

  Widget _buildSectionHeader() {
    final subtitle = _tab == _MarketplaceTab.recommended
        ? 'เลือกผู้ช่วยที่เหมาะสมจากคะแนน ความใกล้ และประสบการณ์'
        : 'ค้นหาผู้ช่วยด้วยชื่อ เบอร์โทร หรือรหัสผู้ใช้';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.indigo.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tab == _MarketplaceTab.recommended
                  ? 'ผู้ช่วยแนะนำสำหรับคลินิก'
                  : 'ค้นหาผู้ช่วย',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.indigo.shade900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.indigo.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelperCard(Map<String, dynamic> item) {
    final stats = _stats(item);
    final levelText = _levelLabel(item);
    final trustScore = _scoreText(item);
    final scoreColor = _scoreColor(item);
    final roleText = _translateRole(item['role']);
    final nearbyText = _nearbyLabel(item);
    final recommendationBadges = _recommendationBadges(item);
    final rank = _rankOf(item);
    final subtitle = _displaySubtitle(item);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      elevation: 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recommendationBadges.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recommendationBadges
                    .map(
                      (e) => _buildTag(
                        e,
                        background: e == 'แนะนำ'
                            ? Colors.purple.shade50
                            : Colors.green.shade50,
                        foreground: e == 'แนะนำ'
                            ? Colors.purple.shade800
                            : Colors.green.shade800,
                        border: e == 'แนะนำ'
                            ? Colors.purple.shade200
                            : Colors.green.shade200,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 10),
            ] else if (nearbyText.isNotEmpty) ...[
              _buildTag(
                nearbyText,
                background: Colors.green.shade50,
                foreground: Colors.green.shade800,
                border: Colors.green.shade200,
              ),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'บทบาท: $roleText',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scoreColor.withAlpha(26),
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
                        'คะแนน',
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
            if (rank != null) ...[
              const SizedBox(height: 6),
              Text(
                'คะแนนแนะนำ: ${rank.finalScore.toStringAsFixed(1)}',
                style: TextStyle(
                  color: Colors.purple.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatPill('งานทั้งหมด', '${_i(stats['totalShifts'])}'),
                _buildStatPill('สำเร็จ', '${_i(stats['completed'])}'),
                _buildStatPill('มาสาย', '${_i(stats['late'])}'),
                _buildStatPill('ไม่มาตามนัด', '${_i(stats['noShow'])}'),
                if (_distanceText(item).isNotEmpty)
                  _buildStatPill('ระยะทาง', _distanceText(item)),
              ],
            ),
            if (rank != null && rank.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                rank.reasons.take(2).join(' • '),
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
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

  Widget _buildSortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: HelperSortMode.values.map((mode) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_sortLabel(mode)),
                selected: _sortMode == mode,
                onSelected: (_) => _changeSortMode(mode),
              ),
            );
          }).toList(),
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
            Center(child: Text('ยังไม่พบข้อมูลผู้ช่วย')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCurrentTab,
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildHelperCard(items[i]),
      ),
    );
  }

  Widget _buildInfoBanner({
    required Color background,
    required Color border,
    required Color foreground,
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasClinicLocation = _clinicLocation != null;

    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('ค้นหาผู้ช่วย'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!hasClinicLocation && !_loading)
                _buildInfoBanner(
                  background: Colors.orange.shade50,
                  border: Colors.orange.shade200,
                  foreground: Colors.orange.shade900,
                  icon: Icons.location_off_outlined,
                  text:
                      'ยังไม่พบพิกัดคลินิกที่บันทึกไว้ ระบบยังค้นหาผู้ช่วยได้ แต่ข้อมูลระยะทางและการจัดอันดับตามความใกล้อาจไม่ครบถ้วน',
                ),
              if (_usingGpsFallback && !_loading)
                _buildInfoBanner(
                  background: Colors.blue.shade50,
                  border: Colors.blue.shade200,
                  foreground: Colors.blue.shade900,
                  icon: Icons.my_location_outlined,
                  text:
                      'ขณะนี้กำลังใช้ตำแหน่งปัจจุบันของอุปกรณ์แทนพิกัดคลินิกที่บันทึกไว้ ระยะทางที่แสดงอาจคลาดเคลื่อนได้เล็กน้อย',
                ),
              _buildSectionHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchHelpers(),
                        decoration: InputDecoration(
                          hintText: 'ค้นหาด้วยชื่อ เบอร์โทร หรือรหัสผู้ใช้',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _loadingSearch ? null : _searchHelpers,
                        child: _loadingSearch
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('ค้นหา'),
                      ),
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
                        label: const Text('ผู้ช่วยแนะนำ'),
                        selected: _tab == _MarketplaceTab.recommended,
                        onSelected: (_) {
                          _dismissKeyboard();
                          setState(() {
                            _tab = _MarketplaceTab.recommended;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('ผลการค้นหา'),
                        selected: _tab == _MarketplaceTab.search,
                        onSelected: (_) {
                          _dismissKeyboard();
                          setState(() {
                            _tab = _MarketplaceTab.search;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              _buildSortBar(),
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
        ),
      ),
    );
  }
}

enum _MarketplaceTab {
  recommended,
  search,
}