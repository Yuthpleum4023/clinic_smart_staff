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
  static ApiClient get _client =>
      ApiClient(baseUrl: ApiConfig.scoreBaseUrl);

  // ============================================================
  // SEARCH HELPERS (GLOBAL)
  // GET /helpers/search?q=...
  // ============================================================
  static Future<List<Map<String, dynamic>>> searchHelpers({
    required String q,
    int limit = 20,
  }) async {
    final query = q.trim();
    if (query.isEmpty) return [];

    final decoded = await _client.get(
      "/helpers/search",
      auth: true,
      query: {
        "q": query,
        "limit": "$limit",
      },
    );

    final items = decoded["items"];

    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }

  // ============================================================
  // GET HELPER TRUST SCORE
  // GET /helpers/:userId/score
  // ============================================================
  static Future<Map<String, dynamic>?> getHelperScore(
    String userId,
  ) async {
    final id = userId.trim();
    if (id.isEmpty) return null;

    final decoded = await _client.get(
      "/helpers/$id/score",
      auth: true,
    );

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return null;
  }

  // ============================================================
  // GET HELPER RECOMMENDATIONS
  // GET /recommendations?clinicId=...
  // ============================================================
  static Future<List<Map<String, dynamic>>> getRecommendations({
    required String clinicId,
  }) async {
    final cid = clinicId.trim();
    if (cid.isEmpty) return [];

    final decoded = await _client.get(
      "/recommendations",
      auth: true,
      query: {
        "clinicId": cid,
      },
    );

    final items = decoded["recommended"];

    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }
}