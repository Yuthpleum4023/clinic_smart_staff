// INVENTORY_PHASE1_FLUTTER_V2
// lib/api/inventory_api.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/models/inventory_item_model.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class InventoryApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const InventoryApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

class InventoryApi {
  static const Duration _timeout = Duration(seconds: 20);

  // Values below are detected from the current backend source at patch time.
  static const String _stockItemBodyKey = 'stockItemId';
  static const String _stockQuantityBodyKey = 'quantity';
  static const bool _idempotencyInBody = true;
  static const bool _idempotencyInHeader = true;

  static String _baseUrl() {
    var value = ApiConfig.inventoryBaseUrl.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final baseUri = Uri.parse('${_baseUrl()}$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return baseUri;
    }
    return baseUri.replace(queryParameters: queryParameters);
  }

  static Future<Map<String, String>> _headers() async {
    final token = (await AuthStorage.getToken())?.trim() ?? '';
    if (token.isEmpty || token.toLowerCase() == 'null') {
      throw const InventoryApiException(
        statusCode: 401,
        code: 'AUTH_REQUIRED',
        message: 'กรุณาเข้าสู่ระบบอีกครั้ง',
      );
    }

    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}

    return <String, dynamic>{};
  }

  static InventoryApiException _httpError(http.Response response) {
    final body = _decodeObject(response.body);
    final code = (body['code'] ?? 'HTTP_${response.statusCode}')
        .toString()
        .trim();
    final message =
        (body['message'] ?? body['error'] ?? 'เรียกข้อมูลคลังสินค้าไม่สำเร็จ')
            .toString()
            .trim();

    return InventoryApiException(
      statusCode: response.statusCode,
      code: code.isEmpty ? 'HTTP_${response.statusCode}' : code,
      message: message.isEmpty ? 'เรียกข้อมูลคลังสินค้าไม่สำเร็จ' : message,
    );
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw _httpError(response);
  }

  static List<dynamic>? _extractItems(Map<String, dynamic> body) {
    final direct = body['items'];
    if (direct is List) return direct;

    final data = body['data'];
    if (data is Map) {
      final nested = data['items'];
      if (nested is List) return nested;
    }

    return null;
  }

  static Future<List<InventoryItem>> listItems({
    String search = '',
    bool? active,
    bool? lowStock,
  }) async {
    final query = <String, String>{};

    final normalizedSearch = search.trim();

    if (normalizedSearch.length > 120) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'INVALID_ITEM_SEARCH',
        message: 'คำค้นหายาวเกินไป',
      );
    }

    if (normalizedSearch.isNotEmpty) {
      query['search'] = normalizedSearch;
    }

    if (active != null) {
      query['active'] = active ? 'true' : 'false';
    }

    if (lowStock != null) {
      query['lowStock'] = lowStock ? 'true' : 'false';
    }

    final response = await http
        .get(_uri('/api/inventory/items', query), headers: await _headers())
        .timeout(_timeout);

    _ensureSuccess(response);

    final body = _decodeObject(response.body);
    final rawItems = _extractItems(body);

    if (rawItems == null) {
      throw InventoryApiException(
        statusCode: response.statusCode,
        code: 'INVALID_RESPONSE',
        message: 'รูปแบบข้อมูลรายการคลังสินค้าไม่ถูกต้อง',
      );
    }

    return rawItems
        .whereType<Map>()
        .map((item) => InventoryItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> stockIn({
    required String stockItemId,
    required double quantity,
    required String idempotencyKey,
    String referenceNo = '',
    String lotNo = '',
    String supplier = '',
    String reason = '',
    String note = '',
  }) async {
    final itemId = stockItemId.trim();
    final key = idempotencyKey.trim();

    if (itemId.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'ITEM_REQUIRED',
        message: 'ไม่พบรหัสสินค้า',
      );
    }

    if (!quantity.isFinite || quantity <= 0) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'QUANTITY_INVALID',
        message: 'จำนวนรับเข้าต้องมากกว่า 0',
      );
    }

    if (key.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'IDEMPOTENCY_KEY_REQUIRED',
        message: 'ไม่พบรหัสป้องกันการบันทึกซ้ำ',
      );
    }

    final body = <String, dynamic>{
      _stockItemBodyKey: itemId,
      _stockQuantityBodyKey: quantity,
    };

    if (_idempotencyInBody) {
      body['idempotencyKey'] = key;
    }

    void addText(String name, String value) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) body[name] = normalized;
    }

    addText('referenceNo', referenceNo);
    addText('lotNo', lotNo);
    addText('supplier', supplier);
    addText('reason', reason);
    addText('note', note);

    final headers = await _headers();
    if (_idempotencyInHeader) {
      headers['Idempotency-Key'] = key;
    }

    final response = await http
        .post(
          _uri('/api/inventory/stock/in'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    _ensureSuccess(response);
    return _decodeObject(response.body);
  }

  static Future<Map<String, dynamic>> consume({
    required String stockItemId,
    required double quantity,
    required String idempotencyKey,
    required String reason,
    String referenceNo = '',
    String lotNo = '',
    String note = '',
  }) async {
    final itemId = stockItemId.trim();
    final key = idempotencyKey.trim();
    final normalizedReason = reason.trim();

    if (itemId.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'ITEM_REQUIRED',
        message: 'ไม่พบรหัสสินค้า',
      );
    }

    if (!quantity.isFinite || quantity <= 0) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'QUANTITY_INVALID',
        message: 'จำนวนเบิกต้องมากกว่า 0',
      );
    }

    if (key.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'IDEMPOTENCY_KEY_REQUIRED',
        message: 'ไม่พบรหัสป้องกันการบันทึกซ้ำ',
      );
    }

    if (normalizedReason.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'REASON_REQUIRED',
        message: 'กรุณาระบุเหตุผลในการเบิกใช้',
      );
    }

    final body = <String, dynamic>{
      _stockItemBodyKey: itemId,
      _stockQuantityBodyKey: quantity,
      'reason': normalizedReason,
    };

    if (_idempotencyInBody) {
      body['idempotencyKey'] = key;
    }

    void addText(String name, String value) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        body[name] = normalized;
      }
    }

    addText('referenceNo', referenceNo);
    addText('lotNo', lotNo);
    addText('note', note);

    final headers = await _headers();

    if (_idempotencyInHeader) {
      headers['Idempotency-Key'] = key;
    }

    final response = await http
        .post(
          _uri('/api/inventory/stock/consume'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    _ensureSuccess(response);
    return _decodeObject(response.body);
  }

  // INVENTORY_ADMIN_ITEM_UI_V2
  // INVENTORY_SERVER_ITEM_CODE_UI_V2
  static Future<Map<String, dynamic>> createItem({
    required String name,
    String category = '',
    required String unit,
    required double minimumQty,
    required bool lowStockAlertEnabled,
  }) async {
    final normalizedName = name.trim();
    final normalizedUnit = unit.trim();

    if (normalizedName.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'ITEM_NAME_REQUIRED',
        message: 'กรุณาระบุชื่อสินค้า',
      );
    }

    if (normalizedUnit.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'ITEM_UNIT_REQUIRED',
        message: 'กรุณาระบุหน่วยสินค้า',
      );
    }

    if (!minimumQty.isFinite || minimumQty < 0) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'MINIMUM_QTY_INVALID',
        message: 'ระดับแจ้งเตือนต้องไม่น้อยกว่า 0',
      );
    }

    final body = <String, dynamic>{
      'name': normalizedName,
      'unit': normalizedUnit,
      'minimumQty': minimumQty,
      'lowStockAlertEnabled': lowStockAlertEnabled,
    };

    final normalizedCategory = category.trim();
    if (normalizedCategory.isNotEmpty) {
      body['category'] = normalizedCategory;
    }

    final response = await http
        .post(
          _uri('/api/inventory/items'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    _ensureSuccess(response);
    return _decodeObject(response.body);
  }

  static Future<Map<String, dynamic>> setItemActive({
    required String stockItemId,
    required bool active,
  }) async {
    final itemId = stockItemId.trim();

    if (itemId.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'ITEM_REQUIRED',
        message: 'ไม่พบรหัสสินค้า',
      );
    }

    final response = await http
        .patch(
          _uri('/api/inventory/items/${Uri.encodeComponent(itemId)}'),
          headers: await _headers(),
          body: jsonEncode(<String, dynamic>{'active': active}),
        )
        .timeout(_timeout);

    _ensureSuccess(response);
    return _decodeObject(response.body);
  }

  static Future<Map<String, dynamic>> updateThreshold({
    required String stockItemId,
    required double minimumQty,
    required bool lowStockAlertEnabled,
  }) async {
    final itemId = stockItemId.trim();

    if (itemId.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'ITEM_REQUIRED',
        message: 'ไม่พบรหัสสินค้า',
      );
    }

    if (!minimumQty.isFinite || minimumQty < 0) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'MINIMUM_QTY_INVALID',
        message: 'ระดับแจ้งเตือนต้องไม่น้อยกว่า 0',
      );
    }

    final response = await http
        .patch(
          _uri('/api/inventory/items/${Uri.encodeComponent(itemId)}/threshold'),
          headers: await _headers(),
          body: jsonEncode(<String, dynamic>{
            'minimumQty': minimumQty,
            'lowStockAlertEnabled': lowStockAlertEnabled,
          }),
        )
        .timeout(_timeout);

    _ensureSuccess(response);
    return _decodeObject(response.body);
  }

  static Future<Map<String, dynamic>> getOperationalStockCard(
    String stockItemId,
  ) async {
    final itemId = stockItemId.trim();
    if (itemId.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'ITEM_REQUIRED',
        message: 'ไม่พบรหัสสินค้า',
      );
    }

    final response = await http
        .get(
          _uri(
            '/api/inventory/items/${Uri.encodeComponent(itemId)}/card',
            const <String, String>{'mode': 'operational'},
          ),
          headers: await _headers(),
        )
        .timeout(_timeout);

    _ensureSuccess(response);

    final body = _decodeObject(response.body);
    final rawCard = body['stockCard'];
    if (rawCard is Map<String, dynamic>) return rawCard;
    if (rawCard is Map) return Map<String, dynamic>.from(rawCard);

    throw InventoryApiException(
      statusCode: response.statusCode,
      code: 'INVALID_RESPONSE',
      message: 'รูปแบบข้อมูล Stock Card ไม่ถูกต้อง',
    );
  }

  // INVENTORY_PHASE2_FLUTTER_INTEGRATION_UI_V1
  static Future<List<Map<String, dynamic>>> listIntegrationConnectors() async {
    final response = await http
        .get(
          _uri('/api/inventory/integrations/admin/connectors'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    _ensureSuccess(response);

    final body = _decodeObject(response.body);
    final raw = body['connectors'];

    if (raw is! List) {
      throw InventoryApiException(
        statusCode: response.statusCode,
        code: 'INVALID_RESPONSE',
        message: 'รูปแบบข้อมูลระบบเชื่อมต่อไม่ถูกต้อง',
      );
    }

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> getIntegrationConnectorHealth(
    String connectorId,
  ) async {
    final id = connectorId.trim();
    if (id.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'CONNECTOR_REQUIRED',
        message: 'ไม่พบรหัสระบบเชื่อมต่อ',
      );
    }

    final response = await http
        .get(
          _uri(
            '/api/inventory/integrations/admin/connectors/'
            '${Uri.encodeComponent(id)}/health',
          ),
          headers: await _headers(),
        )
        .timeout(_timeout);

    _ensureSuccess(response);

    final body = _decodeObject(response.body);
    final raw = body['health'];

    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);

    throw InventoryApiException(
      statusCode: response.statusCode,
      code: 'INVALID_RESPONSE',
      message: 'รูปแบบข้อมูลสถานะระบบเชื่อมต่อไม่ถูกต้อง',
    );
  }

  static Future<List<Map<String, dynamic>>> listIntegrationMappings(
    String connectorId,
  ) async {
    final id = connectorId.trim();
    if (id.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'CONNECTOR_REQUIRED',
        message: 'ไม่พบรหัสระบบเชื่อมต่อ',
      );
    }

    final response = await http
        .get(
          _uri(
            '/api/inventory/integrations/admin/connectors/'
            '${Uri.encodeComponent(id)}/mappings',
          ),
          headers: await _headers(),
        )
        .timeout(_timeout);

    _ensureSuccess(response);

    final body = _decodeObject(response.body);
    final raw = body['mappings'];

    if (raw is! List) {
      throw InventoryApiException(
        statusCode: response.statusCode,
        code: 'INVALID_RESPONSE',
        message: 'รูปแบบข้อมูลการจับคู่สินค้าไม่ถูกต้อง',
      );
    }

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>> listIntegrationEvents({
    required String connectorId,
    String status = '',
    int limit = 50,
  }) async {
    final id = connectorId.trim();
    if (id.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'CONNECTOR_REQUIRED',
        message: 'ไม่พบรหัสระบบเชื่อมต่อ',
      );
    }

    final safeLimit = limit.clamp(1, 100);
    final query = <String, String>{'limit': safeLimit.toString()};

    final normalizedStatus = status.trim();
    if (normalizedStatus.isNotEmpty) {
      query['status'] = normalizedStatus;
    }

    final response = await http
        .get(
          _uri(
            '/api/inventory/integrations/admin/connectors/'
            '${Uri.encodeComponent(id)}/events',
            query,
          ),
          headers: await _headers(),
        )
        .timeout(_timeout);

    _ensureSuccess(response);

    final body = _decodeObject(response.body);
    final raw = body['events'];

    if (raw is! List) {
      throw InventoryApiException(
        statusCode: response.statusCode,
        code: 'INVALID_RESPONSE',
        message: 'รูปแบบข้อมูลเหตุการณ์เชื่อมต่อไม่ถูกต้อง',
      );
    }

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> getIntegrationEvent(
    String eventId,
  ) async {
    final id = eventId.trim();
    if (id.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'EVENT_REQUIRED',
        message: 'ไม่พบรหัสเหตุการณ์',
      );
    }

    final response = await http
        .get(
          _uri(
            '/api/inventory/integrations/admin/events/'
            '${Uri.encodeComponent(id)}',
          ),
          headers: await _headers(),
        )
        .timeout(_timeout);

    _ensureSuccess(response);

    final body = _decodeObject(response.body);
    final raw = body['event'];

    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);

    throw InventoryApiException(
      statusCode: response.statusCode,
      code: 'INVALID_RESPONSE',
      message: 'รูปแบบข้อมูลเหตุการณ์ไม่ถูกต้อง',
    );
  }

  static Future<Map<String, dynamic>> reprocessIntegrationEvent(
    String eventId,
  ) async {
    final id = eventId.trim();
    if (id.isEmpty) {
      throw const InventoryApiException(
        statusCode: 400,
        code: 'EVENT_REQUIRED',
        message: 'ไม่พบรหัสเหตุการณ์',
      );
    }

    final response = await http
        .post(
          _uri(
            '/api/inventory/integrations/admin/events/'
            '${Uri.encodeComponent(id)}/reprocess',
          ),
          headers: await _headers(),
          body: jsonEncode(const <String, dynamic>{}),
        )
        .timeout(_timeout);

    _ensureSuccess(response);
    return _decodeObject(response.body);
  }
}
