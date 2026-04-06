import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class ReceiptApi {
  static String get baseUrl =>
      '${ApiConfig.payrollBaseUrl}/social-security-receipts';

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getToken();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> _binaryHeaders() async {
    final token = await AuthStorage.getToken();

    return {
      'Accept': 'application/pdf',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Uri _buildUri(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    final qp = <String, String>{};

    queryParameters?.forEach((key, value) {
      final x = (value ?? '').toString().trim();
      if (x.isNotEmpty) {
        qp[key] = x;
      }
    });

    return Uri.parse('$baseUrl$path').replace(
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  static Future<Map<String, dynamic>> createReceipt({
    required String clinicId,
    required String customerName,
    required String serviceMonth,
    required List<Map<String, dynamic>> items,
    String? customerAddress,
    String? servicePeriodText,
    String? note,
    String? clinicName,
    String? clinicBranchName,
    String? clinicAddress,
    String? clinicPhone,
    String? clinicTaxId,
    String? logoUrl,

    // NEW
    String? withholderTaxId,
    String? paymentMethod,
    String? bankName,
    String? accountName,
    String? accountNumber,
    String? paymentReference,

    // optional nested payloads for backend compatibility
    Map<String, dynamic>? clinicSnapshot,
    Map<String, dynamic>? customerSnapshot,
    Map<String, dynamic>? paymentInfo,

    bool withholdingTaxEnabled = false,
    double withholdingTaxAmount = 0,
  }) async {
    final normalizedClinicSnapshot = <String, dynamic>{
      if ((clinicName ?? '').trim().isNotEmpty) 'clinicName': clinicName!.trim(),
      if ((clinicBranchName ?? '').trim().isNotEmpty)
        'clinicBranchName': clinicBranchName!.trim(),
      if ((clinicAddress ?? '').trim().isNotEmpty)
        'clinicAddress': clinicAddress!.trim(),
      if ((clinicPhone ?? '').trim().isNotEmpty)
        'clinicPhone': clinicPhone!.trim(),
      if ((clinicTaxId ?? '').trim().isNotEmpty)
        'clinicTaxId': clinicTaxId!.trim(),
      if ((logoUrl ?? '').trim().isNotEmpty) 'logoUrl': logoUrl!.trim(),
      if ((withholderTaxId ?? '').trim().isNotEmpty)
        'withholderTaxId': withholderTaxId!.trim(),
      ...?clinicSnapshot,
    };

    final normalizedCustomerSnapshot = <String, dynamic>{
      'customerName': customerName.trim(),
      if ((customerAddress ?? '').trim().isNotEmpty)
        'customerAddress': customerAddress!.trim(),
      ...?customerSnapshot,
    };

    final normalizedPaymentInfo = <String, dynamic>{
      if ((paymentMethod ?? '').trim().isNotEmpty)
        'method': paymentMethod!.trim(),
      if ((bankName ?? '').trim().isNotEmpty) 'bankName': bankName!.trim(),
      if ((accountName ?? '').trim().isNotEmpty)
        'accountName': accountName!.trim(),
      if ((accountNumber ?? '').trim().isNotEmpty)
        'accountNumber': accountNumber!.trim(),
      if ((paymentReference ?? '').trim().isNotEmpty)
        'transferRef': paymentReference!.trim(),
      ...?paymentInfo,
    };

    final body = <String, dynamic>{
      'clinicId': clinicId.trim(),
      'serviceMonth': serviceMonth.trim(),
      'customerName': customerName.trim(),
      'customerAddress': (customerAddress ?? '').trim(),
      'items': items,
      'withholdingTaxEnabled': withholdingTaxEnabled,
      'withholdingTaxAmount': withholdingTaxAmount,
      if ((servicePeriodText ?? '').trim().isNotEmpty)
        'servicePeriodText': servicePeriodText!.trim(),
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),

      // top-level fields for controller fallback support
      if ((clinicName ?? '').trim().isNotEmpty) 'clinicName': clinicName!.trim(),
      if ((clinicBranchName ?? '').trim().isNotEmpty)
        'clinicBranchName': clinicBranchName!.trim(),
      if ((clinicAddress ?? '').trim().isNotEmpty)
        'clinicAddress': clinicAddress!.trim(),
      if ((clinicPhone ?? '').trim().isNotEmpty)
        'clinicPhone': clinicPhone!.trim(),
      if ((clinicTaxId ?? '').trim().isNotEmpty)
        'clinicTaxId': clinicTaxId!.trim(),
      if ((logoUrl ?? '').trim().isNotEmpty) 'logoUrl': logoUrl!.trim(),
      if ((withholderTaxId ?? '').trim().isNotEmpty)
        'withholderTaxId': withholderTaxId!.trim(),

      if ((paymentMethod ?? '').trim().isNotEmpty)
        'paymentMethod': paymentMethod!.trim(),
      if ((bankName ?? '').trim().isNotEmpty) 'bankName': bankName!.trim(),
      if ((accountName ?? '').trim().isNotEmpty)
        'accountName': accountName!.trim(),
      if ((accountNumber ?? '').trim().isNotEmpty)
        'accountNumber': accountNumber!.trim(),
      if ((paymentReference ?? '').trim().isNotEmpty)
        'paymentReference': paymentReference!.trim(),

      // nested objects
      'customerSnapshot': normalizedCustomerSnapshot,
      if (normalizedClinicSnapshot.isNotEmpty)
        'clinicSnapshot': normalizedClinicSnapshot,
      if (normalizedPaymentInfo.isNotEmpty) 'paymentInfo': normalizedPaymentInfo,
    };

    final res = await http.post(
      _buildUri(''),
      headers: await _headers(),
      body: jsonEncode(body),
    );

    return _handle(res);
  }

  static Future<Map<String, dynamic>> listReceipts({
    required String clinicId,
    int page = 1,
    int limit = 20,
    String? status,
    String? receiptNo,
    String? customerName,
    String? fromDate,
    String? toDate,
  }) async {
    final res = await http.get(
      _buildUri(
        '',
        queryParameters: {
          'clinicId': clinicId,
          'page': page,
          'limit': limit,
          'status': status,
          'receiptNo': receiptNo,
          'customerName': customerName,
          'fromDate': fromDate,
          'toDate': toDate,
        },
      ),
      headers: await _headers(),
    );

    return _handle(res);
  }

  static Future<Map<String, dynamic>> getReceipt(
    String id, {
    String? clinicId,
  }) async {
    final res = await http.get(
      _buildUri(
        '/$id',
        queryParameters: {
          'clinicId': clinicId,
        },
      ),
      headers: await _headers(),
    );

    return _handle(res);
  }

  static Future<Map<String, dynamic>> generatePdf(
    String id, {
    String? clinicId,
    String? logoUrl,
  }) async {
    final res = await http.post(
      _buildUri(
        '/$id/generate-pdf',
        queryParameters: {
          'clinicId': clinicId,
        },
      ),
      headers: await _headers(),
      body: jsonEncode({
        if ((clinicId ?? '').trim().isNotEmpty) 'clinicId': clinicId!.trim(),
        if ((logoUrl ?? '').trim().isNotEmpty) 'logoUrl': logoUrl!.trim(),
      }),
    );

    return _handle(res);
  }

  static Future<Map<String, dynamic>> getPdfInfo(
    String id, {
    String? clinicId,
  }) async {
    final res = await http.get(
      _buildUri(
        '/$id/pdf',
        queryParameters: {
          'clinicId': clinicId,
        },
      ),
      headers: await _headers(),
    );

    return _handle(res);
  }

  static String pdfStreamUrl(
    String id, {
    String? clinicId,
    bool download = false,
  }) {
    final uri = _buildUri(
      '/$id/pdf/open',
      queryParameters: {
        'clinicId': clinicId,
        'download': download ? 'true' : 'false',
      },
    );

    return uri.toString();
  }

  static Future<Uint8List> fetchPdfBytes(
    String id, {
    String? clinicId,
    bool download = false,
  }) async {
    final res = await http.get(
      _buildUri(
        '/$id/pdf/open',
        queryParameters: {
          'clinicId': clinicId,
          'download': download ? 'true' : 'false',
        },
      ),
      headers: await _binaryHeaders(),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }

    String message = 'ดาวน์โหลด PDF ไม่สำเร็จ';

    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) {
        final msg = decoded['message']?.toString().trim() ?? '';
        if (msg.isNotEmpty) {
          message = msg;
        }
      }
    } catch (_) {
      final raw = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
      if (raw.isNotEmpty) {
        message = raw;
      }
    }

    throw Exception(message);
  }

  static Future<Map<String, dynamic>> voidReceipt(
    String id, {
    String? clinicId,
    String? voidReason,
  }) async {
    final res = await http.post(
      _buildUri(
        '/$id/void',
        queryParameters: {
          'clinicId': clinicId,
        },
      ),
      headers: await _headers(),
      body: jsonEncode({
        if ((clinicId ?? '').trim().isNotEmpty) 'clinicId': clinicId!.trim(),
        if ((voidReason ?? '').trim().isNotEmpty)
          'voidReason': voidReason!.trim(),
      }),
    );

    return _handle(res);
  }

  static Map<String, dynamic> _handle(http.Response res) {
    dynamic decoded;

    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{
        'ok': true,
        'raw': res.body,
      };
    }

    String message = 'Request failed';
    if (decoded is Map) {
      final msg = decoded['message']?.toString().trim() ?? '';
      if (msg.isNotEmpty) {
        message = msg;
      }
    } else if (res.body.trim().isNotEmpty) {
      message = res.body.trim();
    }

    throw Exception(message);
  }
}