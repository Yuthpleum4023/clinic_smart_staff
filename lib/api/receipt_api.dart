import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:clinic_smart_staff/api/api_config.dart';
import 'package:clinic_smart_staff/services/auth_storage.dart';

class ReceiptApi {
  static String get baseUrl =>
      '${ApiConfig.payrollBaseUrl}/social-security-receipts';

  static const Duration _timeout = Duration(seconds: 25);

  static Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.getToken();

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
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

  static bool _looksLikeHtml(String text) {
    final s = text.trim().toLowerCase();
    return s.startsWith('<!doctype html') ||
        s.startsWith('<html') ||
        s.contains('<head>') ||
        s.contains('<body>') ||
        s.contains('<title>502') ||
        s.contains('<title>503') ||
        s.contains('<title>504');
  }

  static String _friendlyHttpMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'ข้อมูลไม่ถูกต้อง';
      case 401:
        return 'กรุณาเข้าสู่ระบบใหม่';
      case 403:
        return 'ไม่มีสิทธิ์ใช้งาน';
      case 404:
        return 'ไม่พบข้อมูลที่ต้องการ';
      case 409:
        return 'ข้อมูลซ้ำหรือขัดแย้งกับข้อมูลเดิม';
      case 500:
        return 'ระบบเซิร์ฟเวอร์ขัดข้อง';
      case 502:
      case 503:
      case 504:
        return 'เซิร์ฟเวอร์ใบเสร็จยังไม่พร้อมใช้งาน กรุณาลองใหม่อีกครั้ง';
      default:
        return 'Request failed ($statusCode)';
    }
  }

  static String _extractErrorMessage(http.Response res) {
    final raw = res.body.trim();

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map) {
      final msg = decoded['message']?.toString().trim() ?? '';
      if (msg.isNotEmpty) return msg;

      final err = decoded['error']?.toString().trim() ?? '';
      if (err.isNotEmpty) return err;
    }

    if (raw.isNotEmpty && !_looksLikeHtml(raw)) {
      return raw;
    }

    return _friendlyHttpMessage(res.statusCode);
  }

  static String _extractBinaryErrorMessage(http.Response res) {
    final raw = utf8.decode(res.bodyBytes, allowMalformed: true).trim();

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map) {
      final msg = decoded['message']?.toString().trim() ?? '';
      if (msg.isNotEmpty) return msg;

      final err = decoded['error']?.toString().trim() ?? '';
      if (err.isNotEmpty) return err;
    }

    if (raw.isNotEmpty && !_looksLikeHtml(raw)) {
      return raw;
    }

    return _friendlyHttpMessage(res.statusCode);
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
    String? withholderTaxId,
    String? paymentMethod,
    String? bankName,
    String? accountName,
    String? accountNumber,
    String? paymentReference,
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
      'customerSnapshot': normalizedCustomerSnapshot,
      if (normalizedClinicSnapshot.isNotEmpty)
        'clinicSnapshot': normalizedClinicSnapshot,
      if (normalizedPaymentInfo.isNotEmpty) 'paymentInfo': normalizedPaymentInfo,
    };

    try {
      final res = await http
          .post(
            _buildUri(''),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      return _handle(res);
    } catch (e) {
      throw Exception('สร้างใบเสร็จไม่สำเร็จ: $e');
    }
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
    try {
      final res = await http
          .get(
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
          )
          .timeout(_timeout);

      return _handle(res);
    } catch (e) {
      throw Exception('โหลดรายการใบเสร็จไม่สำเร็จ: $e');
    }
  }

  static Future<Map<String, dynamic>> getReceipt(
    String id, {
    String? clinicId,
  }) async {
    try {
      final res = await http
          .get(
            _buildUri(
              '/$id',
              queryParameters: {
                'clinicId': clinicId,
              },
            ),
            headers: await _headers(),
          )
          .timeout(_timeout);

      return _handle(res);
    } catch (e) {
      throw Exception('โหลดรายละเอียดใบเสร็จไม่สำเร็จ: $e');
    }
  }

  static Future<Map<String, dynamic>> generatePdf(
    String id, {
    String? clinicId,
    String? logoUrl,
  }) async {
    try {
      final res = await http
          .post(
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
          )
          .timeout(_timeout);

      return _handle(res);
    } catch (e) {
      throw Exception('สร้าง PDF ไม่สำเร็จ: $e');
    }
  }

  static Future<Map<String, dynamic>> getPdfInfo(
    String id, {
    String? clinicId,
  }) async {
    try {
      final res = await http
          .get(
            _buildUri(
              '/$id/pdf',
              queryParameters: {
                'clinicId': clinicId,
              },
            ),
            headers: await _headers(),
          )
          .timeout(_timeout);

      return _handle(res);
    } catch (e) {
      throw Exception('โหลดข้อมูล PDF ไม่สำเร็จ: $e');
    }
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
    try {
      final res = await http
          .get(
            _buildUri(
              '/$id/pdf/open',
              queryParameters: {
                'clinicId': clinicId,
                'download': download ? 'true' : 'false',
              },
            ),
            headers: await _binaryHeaders(),
          )
          .timeout(_timeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final contentType = (res.headers['content-type'] ?? '').toLowerCase();
        if (contentType.contains('application/pdf')) {
          return res.bodyBytes;
        }

        final maybeText = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (_looksLikeHtml(maybeText)) {
          throw Exception('เซิร์ฟเวอร์ PDF ยังไม่พร้อมใช้งาน กรุณาลองใหม่อีกครั้ง');
        }

        return res.bodyBytes;
      }

      throw Exception(_extractBinaryErrorMessage(res));
    } catch (e) {
      throw Exception('ดาวน์โหลด PDF ไม่สำเร็จ: $e');
    }
  }

  static Future<Map<String, dynamic>> voidReceipt(
    String id, {
    String? clinicId,
    String? voidReason,
  }) async {
    try {
      final res = await http
          .post(
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
          )
          .timeout(_timeout);

      return _handle(res);
    } catch (e) {
      throw Exception('ยกเลิกใบเสร็จไม่สำเร็จ: $e');
    }
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

      if (_looksLikeHtml(res.body)) {
        throw Exception('เซิร์ฟเวอร์ส่งข้อมูลไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง');
      }

      return <String, dynamic>{
        'ok': true,
        'raw': res.body,
      };
    }

    throw Exception(_extractErrorMessage(res));
  }
}