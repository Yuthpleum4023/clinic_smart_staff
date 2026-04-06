// lib/api/helper_marketplace_api.dart
//
// ============================================================
// GLOBAL HELPER MARKETPLACE API
//
// ใช้กับ score_service
// - ค้น helper ทั้งระบบ
// - ดึง trust score
// - ดึง helper recommendations
//
// Requires:
// ApiClient
// ApiConfig
// ============================================================

import 'api_client.dart';
import 'api_config.dart';

class HelperMarketplaceApi {
  static ApiClient get _client => ApiClient(baseUrl: ApiConfig.scoreBaseUrl);

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static double? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _extractListFromDecoded(
    dynamic decoded, {
    List<String> preferredKeys = const [],
  }) {
    final root = _asMap(decoded);

    for (final key in preferredKeys) {
      final list = _asMapList(root[key]);
      if (list.isNotEmpty) return list;
    }

    for (final key in const [
      'items',
      'recommended',
      'results',
      'data',
      'helpers',
    ]) {
      final list = _asMapList(root[key]);
      if (list.isNotEmpty) return list;
    }

    if (decoded is List) {
      return _asMapList(decoded);
    }

    return <Map<String, dynamic>>[];
  }

  static Map<String, dynamic> _normalizeStats(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return {
        'totalShifts': raw['totalShifts'] ?? raw['jobs'] ?? raw['totalJobs'] ?? 0,
        'completed': raw['completed'] ?? raw['success'] ?? 0,
        'late': raw['late'] ?? 0,
        'noShow': raw['noShow'] ?? raw['no_show'] ?? 0,
      };
    }

    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      return {
        'totalShifts': m['totalShifts'] ?? m['jobs'] ?? m['totalJobs'] ?? 0,
        'completed': m['completed'] ?? m['success'] ?? 0,
        'late': m['late'] ?? 0,
        'noShow': m['noShow'] ?? m['no_show'] ?? 0,
      };
    }

    return {
      'totalShifts': 0,
      'completed': 0,
      'late': 0,
      'noShow': 0,
    };
  }

  static Map<String, dynamic> _normalizeHelperItem(Map<String, dynamic> item) {
    final out = Map<String, dynamic>.from(item);

    final location = _asMap(out['location']);
    final helperLocation = _asMap(out['helperLocation']);
    final profileLocation = _asMap(out['profileLocation']);

    final userId = _s(
      out['userId'] ?? out['_id'] ?? out['id'] ?? out['helperUserId'],
    );
    final staffId = _s(out['staffId'] ?? out['employeeId']);

    final fullName = _s(
      out['fullName'] ?? out['name'] ?? out['helperName'],
    );
    final phone = _s(out['phone'] ?? out['mobile']);
    final role = _s(out['role']).isNotEmpty ? _s(out['role']) : 'helper';

    final district = _s(
      out['district'] ??
          out['helperDistrict'] ??
          location['district'] ??
          location['amphoe'] ??
          helperLocation['district'] ??
          helperLocation['amphoe'] ??
          profileLocation['district'] ??
          profileLocation['amphoe'],
    );

    final province = _s(
      out['province'] ??
          out['helperProvince'] ??
          location['province'] ??
          location['changwat'] ??
          helperLocation['province'] ??
          helperLocation['changwat'] ??
          profileLocation['province'] ??
          profileLocation['changwat'],
    );

    final address = _s(
      out['address'] ??
          out['helperAddress'] ??
          location['address'] ??
          location['fullAddress'] ??
          helperLocation['address'] ??
          helperLocation['fullAddress'] ??
          profileLocation['address'] ??
          profileLocation['fullAddress'],
    );

    final locationLabel = _s(
      out['locationLabel'] ??
          out['helperLocationLabel'] ??
          out['profileLocationLabel'] ??
          location['label'] ??
          location['locationLabel'] ??
          helperLocation['label'] ??
          helperLocation['locationLabel'] ??
          profileLocation['label'] ??
          profileLocation['locationLabel'],
    );

    final areaText = _s(
      out['areaText'] ??
          out['area'] ??
          out['locationText'] ??
          out['districtProvince'],
    );

    final trustScore = out['trustScore'] ?? out['score'] ?? out['globalScore'];
    final level = _s(out['level']);
    final levelLabel = _s(out['levelLabel']);

    final lat = _toNum(
      out['lat'] ??
          out['latitude'] ??
          out['helperLat'] ??
          out['helperLatitude'] ??
          location['lat'] ??
          location['latitude'] ??
          helperLocation['lat'] ??
          helperLocation['latitude'] ??
          profileLocation['lat'] ??
          profileLocation['latitude'],
    );

    final lng = _toNum(
      out['lng'] ??
          out['longitude'] ??
          out['helperLng'] ??
          out['helperLongitude'] ??
          location['lng'] ??
          location['longitude'] ??
          helperLocation['lng'] ??
          helperLocation['longitude'] ??
          profileLocation['lng'] ??
          profileLocation['longitude'],
    );

    final distanceKm = _toNum(
      out['distanceKm'] ??
          out['distance'] ??
          out['distance_km'],
    );

    final distanceText = _s(
      out['distanceText'] ??
          out['distanceLabel'] ??
          out['distance_text'],
    );

    final nearClinic = _toBool(
      out['nearClinic'] ?? out['isNearClinic'],
    );

    out['userId'] = userId;
    out['staffId'] = staffId;
    out['fullName'] = fullName;
    out['phone'] = phone;
    out['role'] = role;

    if (district.isNotEmpty) out['district'] = district;
    if (province.isNotEmpty) out['province'] = province;
    if (address.isNotEmpty) out['address'] = address;
    if (locationLabel.isNotEmpty) out['locationLabel'] = locationLabel;
    if (areaText.isNotEmpty) out['areaText'] = areaText;
    if (distanceText.isNotEmpty) out['distanceText'] = distanceText;

    if (lat != null) out['lat'] = lat;
    if (lng != null) out['lng'] = lng;
    if (distanceKm != null) out['distanceKm'] = distanceKm;

    out['nearClinic'] = nearClinic;

    if (trustScore != null) out['trustScore'] = trustScore;
    if (level.isNotEmpty) out['level'] = level;
    if (levelLabel.isNotEmpty) out['levelLabel'] = levelLabel;

    out['stats'] = _normalizeStats(out['stats']);

    if (out['badges'] is! List) {
      out['badges'] = <dynamic>[];
    }

    if (out['flags'] is! List) {
      out['flags'] = <dynamic>[];
    }

    return out;
  }

  // ============================================================
  // SEARCH HELPERS (GLOBAL)
  // GET /helpers/search?q=...
  // ============================================================
  static Future<List<Map<String, dynamic>>> searchHelpers({
    required String q,
    int limit = 20,
    double? clinicLat,
    double? clinicLng,
  }) async {
    final query = q.trim();
    if (query.isEmpty) return [];

    final params = <String, String>{
      'q': query,
      'limit': '$limit',
    };

    if (clinicLat != null) params['clinicLat'] = clinicLat.toString();
    if (clinicLng != null) params['clinicLng'] = clinicLng.toString();

    final decoded = await _client.get(
      '/helpers/search',
      auth: true,
      query: params,
    );

    final items = _extractListFromDecoded(
      decoded,
      preferredKeys: const ['items', 'results', 'helpers', 'data'],
    );

    return items.map(_normalizeHelperItem).toList();
  }

  // ============================================================
  // GET HELPER TRUST SCORE
  // GET /helpers/:userId/score
  // ============================================================
  static Future<Map<String, dynamic>?> getHelperScore(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return null;

    final decoded = await _client.get(
      '/helpers/$id/score',
      auth: true,
    );

    final root = _asMap(decoded);
    if (root.isEmpty) return null;

    if (root['item'] is Map || root['data'] is Map || root['score'] is Map) {
      final item = _asMap(
        (root['item'] is Map && _asMap(root['item']).isNotEmpty)
            ? root['item']
            : (root['data'] is Map && _asMap(root['data']).isNotEmpty)
                ? root['data']
                : root['score'],
      );
      return _normalizeHelperItem(item);
    }

    return _normalizeHelperItem(root);
  }

  // ============================================================
  // GET HELPER RECOMMENDATIONS
  // GET /recommendations?clinicId=...
  // ============================================================
  static Future<List<Map<String, dynamic>>> getRecommendations({
    required String clinicId,
    double? clinicLat,
    double? clinicLng,
  }) async {
    final cid = clinicId.trim();
    if (cid.isEmpty) return [];

    final params = <String, String>{
      'clinicId': cid,
    };

    if (clinicLat != null) params['clinicLat'] = clinicLat.toString();
    if (clinicLng != null) params['clinicLng'] = clinicLng.toString();

    final decoded = await _client.get(
      '/recommendations',
      auth: true,
      query: params,
    );

    final items = _extractListFromDecoded(
      decoded,
      preferredKeys: const ['recommended', 'items', 'results', 'data'],
    );

    return items.map(_normalizeHelperItem).toList();
  }
}