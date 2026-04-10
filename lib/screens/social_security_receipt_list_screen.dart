import 'package:flutter/material.dart';

import 'package:clinic_smart_staff/api/receipt_api.dart';
import 'package:clinic_smart_staff/screens/social_security_receipt_create_screen.dart';
import 'package:clinic_smart_staff/screens/social_security_receipt_detail_screen.dart';

class SocialSecurityReceiptListScreen extends StatefulWidget {
  final String clinicId;

  const SocialSecurityReceiptListScreen({
    super.key,
    required this.clinicId,
  });

  @override
  State<SocialSecurityReceiptListScreen> createState() =>
      _SocialSecurityReceiptListScreenState();
}

class _SocialSecurityReceiptListScreenState
    extends State<SocialSecurityReceiptListScreen> {
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String _error = '';

  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  String _normalizeError(Object e) {
    var msg = e.toString().replaceFirst('Exception: ', '').trim();

    if (msg.isEmpty) {
      return 'เกิดข้อผิดพลาดในการโหลดข้อมูล';
    }

    final lower = msg.toLowerCase();

    if (lower.contains('<!doctype html') ||
        lower.contains('<html') ||
        lower.contains('<head>') ||
        lower.contains('<body>') ||
        lower.contains('502 bad gateway') ||
        lower.contains('503 service unavailable') ||
        lower.contains('504 gateway timeout')) {
      return 'เซิร์ฟเวอร์ใบเสร็จยังไม่พร้อมใช้งาน กรุณาลองใหม่อีกครั้ง';
    }

    if (msg.length > 220) {
      return 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
    }

    return msg;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = '';
      _page = 1;
      _hasMore = false;
      _items.clear();
    });

    try {
      final data = await ReceiptApi.listReceipts(
        clinicId: widget.clinicId,
        page: 1,
      );

      final rows = ((data['receipts'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = data['hasMore'] == true;
        _page = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _normalizeError(e);
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    setState(() {
      _loadingMore = true;
    });

    try {
      final nextPage = _page + 1;
      final data = await ReceiptApi.listReceipts(
        clinicId: widget.clinicId,
        page: nextPage,
      );

      final rows = ((data['receipts'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = data['hasMore'] == true;
        _page = nextPage;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        _normalizeError(e),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
    }
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SocialSecurityReceiptCreateScreen(
          clinicId: widget.clinicId,
        ),
      ),
    );

    await _loadInitial();
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final id = (item['id'] ?? item['_id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SocialSecurityReceiptDetailScreen(
          receiptId: id,
          clinicId: widget.clinicId,
        ),
      ),
    );

    await _loadInitial();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;

    final safeMsg = msg.trim().isEmpty ? 'เกิดข้อผิดพลาด' : msg.trim();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          safeMsg,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  String _safeText(dynamic v, {String fallback = '-'}) {
    final x = (v ?? '').toString().trim();
    return x.isEmpty ? fallback : x;
  }

  String _safeTextOrEmpty(dynamic v) {
    return (v ?? '').toString().trim();
  }

  String _formatMoney(dynamic v) {
    final numValue = num.tryParse('${v ?? 0}') ?? 0;
    return numValue.toStringAsFixed(2);
  }

  String _formatIsoDate(dynamic v, {String fallback = '-'}) {
    final raw = (v ?? '').toString().trim();
    if (raw.isEmpty) return fallback;
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;

    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();

    return '$dd/$mm/$yyyy';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'issued':
        return Colors.green;
      case 'draft':
        return Colors.orange;
      case 'void':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'issued':
        return 'ออกใบเสร็จแล้ว';
      case 'draft':
        return 'ฉบับร่าง';
      case 'void':
        return 'ยกเลิกแล้ว';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  String _paymentMethodLabel(String status) {
    switch (status.toLowerCase()) {
      case 'cash':
        return 'เงินสด';
      case 'transfer':
        return 'โอนเงิน';
      case 'cheque':
        return 'เช็ค';
      case 'other':
        return 'อื่น ๆ';
      default:
        return status.isEmpty ? '-' : status;
    }
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final receiptNo = _safeText(item['receiptNo']);
    final serviceMonth = _safeText(item['serviceMonth']);
    final customerSnapshot =
        Map<String, dynamic>.from((item['customerSnapshot'] as Map?) ?? {});
    final paymentInfo =
        Map<String, dynamic>.from((item['paymentInfo'] as Map?) ?? {});

    final customerName = _safeText(customerSnapshot['customerName']);
    final issueDate = _formatIsoDate(item['issueDate']);
    final subtotal = _formatMoney(item['subtotal']);
    final withholdingTax = _formatMoney(item['withholdingTax']);
    final netAmount = _formatMoney(item['netAmount']);
    final paymentMethod =
        _paymentMethodLabel(_safeTextOrEmpty(paymentInfo['method']));
    final status = _safeText(item['status'], fallback: '');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      receiptNo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 10),
              _InfoRow(label: 'ลูกค้า', value: customerName),
              _InfoRow(label: 'งวดบริการ', value: serviceMonth),
              _InfoRow(label: 'วันที่ออก', value: issueDate),
              _InfoRow(label: 'วิธีชำระ', value: paymentMethod),
              _InfoRow(label: 'รวมเป็นเงิน', value: '$subtotal บาท'),
              _InfoRow(label: 'หัก ณ ที่จ่าย', value: '$withholdingTax บาท'),
              _InfoRow(label: 'ยอดสุทธิ', value: '$netAmount บาท'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.receipt_long, size: 54, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            _error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: _loadInitial,
              child: const Text('ลองใหม่'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error.isNotEmpty) {
      return _buildErrorView();
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Center(
              child: Text(
                'ยังไม่มีใบเสร็จประกันสังคม',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 120) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _items.length + 1,
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: _loadingMore
                      ? const CircularProgressIndicator()
                      : const SizedBox.shrink(),
                ),
              );
            }

            final item = _items[index];
            return _buildCard(item);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ใบเสร็จประกันสังคม'),
        actions: [
          IconButton(
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            tooltip: 'สร้างใบเสร็จ',
          ),
          IconButton(
            onPressed: _loadInitial,
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}