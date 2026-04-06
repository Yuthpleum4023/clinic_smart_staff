import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:clinic_smart_staff/api/receipt_api.dart';

class SocialSecurityReceiptDetailScreen extends StatefulWidget {
  final String receiptId;
  final String clinicId;

  const SocialSecurityReceiptDetailScreen({
    super.key,
    required this.receiptId,
    required this.clinicId,
  });

  @override
  State<SocialSecurityReceiptDetailScreen> createState() =>
      _SocialSecurityReceiptDetailScreenState();
}

class _SocialSecurityReceiptDetailScreenState
    extends State<SocialSecurityReceiptDetailScreen> {
  bool _loading = true;
  bool _generatingPdf = false;
  bool _openingPdf = false;
  bool _printingPdf = false;
  bool _sharingPdf = false;
  bool _voiding = false;

  String _error = '';
  Map<String, dynamic>? _receipt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final data = await ReceiptApi.getReceipt(
        widget.receiptId,
        clinicId: widget.clinicId,
      );

      final receipt = Map<String, dynamic>.from(
        (data['receipt'] as Map?) ?? <String, dynamic>{},
      );

      if (!mounted) return;
      setState(() {
        _receipt = receipt;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
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
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$mi';
  }

  String _pdfFileName() {
    final raw = _safeText(
      _receipt?['receiptNo'],
      fallback: 'social_security_receipt',
    ).trim();

    if (raw.toLowerCase().endsWith('.pdf')) {
      return raw;
    }
    return '$raw.pdf';
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

  String _paymentMethodLabel(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'เงินสด';
      case 'transfer':
        return 'โอนเงิน';
      case 'cheque':
        return 'เช็ค';
      case 'other':
        return 'อื่น ๆ';
      default:
        return method.isEmpty ? '-' : method;
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

  Future<void> _generatePdf() async {
    if (_generatingPdf) return;

    setState(() {
      _generatingPdf = true;
    });

    try {
      final data = await ReceiptApi.generatePdf(
        widget.receiptId,
        clinicId: widget.clinicId,
      );

      final receipt = Map<String, dynamic>.from(
        (data['receipt'] as Map?) ?? <String, dynamic>{},
      );

      if (!mounted) return;
      setState(() {
        _receipt = receipt;
      });

      _showSnack('สร้าง PDF สำเร็จ');
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _generatingPdf = false;
      });
    }
  }

  Future<void> _ensurePdfReady() async {
    final hasPdf = _safeTextOrEmpty(_receipt?['pdfUrl']).isNotEmpty ||
        _safeTextOrEmpty(_receipt?['pdfPath']).isNotEmpty;

    if (hasPdf) return;

    final data = await ReceiptApi.generatePdf(
      widget.receiptId,
      clinicId: widget.clinicId,
    );

    final receipt = Map<String, dynamic>.from(
      (data['receipt'] as Map?) ?? <String, dynamic>{},
    );

    if (!mounted) return;
    setState(() {
      _receipt = receipt;
    });
  }

  Future<Uint8List> _fetchPdfBytesReady() async {
    await _ensurePdfReady();

    return ReceiptApi.fetchPdfBytes(
      widget.receiptId,
      clinicId: widget.clinicId,
      download: false,
    );
  }

  Future<void> _openPdfPreview() async {
    if (_openingPdf) return;

    setState(() {
      _openingPdf = true;
    });

    try {
      final pdfBytes = await _fetchPdfBytesReady();
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ReceiptPdfPreviewScreen(
            title: _pdfFileName(),
            pdfBytes: pdfBytes,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _openingPdf = false;
      });
    }
  }

  Future<void> _printPdf() async {
    if (_printingPdf) return;

    setState(() {
      _printingPdf = true;
    });

    try {
      final pdfBytes = await _fetchPdfBytesReady();

      await Printing.layoutPdf(
        name: _pdfFileName(),
        onLayout: (_) async => pdfBytes,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _printingPdf = false;
      });
    }
  }

  Future<void> _sharePdf() async {
    if (_sharingPdf) return;

    setState(() {
      _sharingPdf = true;
    });

    try {
      final pdfBytes = await _fetchPdfBytesReady();

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: _pdfFileName(),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _sharingPdf = false;
      });
    }
  }

  Future<void> _openPdfExternal() async {
    try {
      String pdfUrl = _safeTextOrEmpty(_receipt?['pdfUrl']);

      if (pdfUrl.isEmpty) {
        final data = await ReceiptApi.getPdfInfo(
          widget.receiptId,
          clinicId: widget.clinicId,
        );

        final pdf = Map<String, dynamic>.from(
          (data['pdf'] as Map?) ?? <String, dynamic>{},
        );

        pdfUrl = _safeTextOrEmpty(pdf['pdfUrl']);

        if (mounted) {
          setState(() {
            _receipt = {
              ...?_receipt,
              'pdfUrl': pdfUrl,
              'pdfGeneratedAt': pdf['pdfGeneratedAt'],
              'pdfPath': pdf['pdfPath'],
            };
          });
        }
      }

      if (pdfUrl.isEmpty) {
        pdfUrl = ReceiptApi.pdfStreamUrl(
          widget.receiptId,
          clinicId: widget.clinicId,
          download: false,
        );
      }

      final uri = Uri.tryParse(pdfUrl);
      if (uri == null) {
        _showSnack('ลิงก์ PDF ไม่ถูกต้อง', isError: true);
        return;
      }

      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!ok) {
        _showSnack('ไม่สามารถเปิด PDF ได้', isError: true);
      }
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _voidReceipt() async {
    if (_voiding) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ยืนยันการยกเลิกใบเสร็จ'),
            content: const Text(
              'เมื่อลบสถานะเป็นยกเลิกแล้ว จะไม่สามารถแก้ไขใบเสร็จนี้กลับมาใช้งานได้ตาม flow ปกติ\n\nต้องการดำเนินการต่อหรือไม่?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ไม่ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ยืนยัน'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    setState(() {
      _voiding = true;
    });

    try {
      final data = await ReceiptApi.voidReceipt(
        widget.receiptId,
        clinicId: widget.clinicId,
      );

      final receipt = Map<String, dynamic>.from(
        (data['receipt'] as Map?) ?? <String, dynamic>{},
      );

      if (!mounted) return;
      setState(() {
        _receipt = receipt;
      });

      _showSnack('ยกเลิกใบเสร็จเรียบร้อยแล้ว');
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _voiding = false;
      });
    }
  }

  Widget _buildActionButtons() {
    final status = _safeTextOrEmpty(_receipt?['status']).toLowerCase();

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: status == 'void' || _generatingPdf ? null : _generatePdf,
            icon: _generatingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            label: Text(_generatingPdf ? 'กำลังสร้าง PDF...' : 'สร้าง PDF'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: status == 'void' || _openingPdf ? null : _openPdfPreview,
            icon: _openingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview),
            label: Text(
              _openingPdf ? 'กำลังเปิดตัวอย่าง...' : 'ดูตัวอย่าง / พิมพ์ PDF',
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: status == 'void' || _printingPdf ? null : _printPdf,
            icon: _printingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
            label: Text(_printingPdf ? 'กำลังเตรียมพิมพ์...' : 'พิมพ์ PDF ทันที'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: status == 'void' || _sharingPdf ? null : _sharePdf,
            icon: _sharingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            label: Text(_sharingPdf ? 'กำลังแชร์ PDF...' : 'แชร์ PDF เป็นไฟล์'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: status == 'void' ? null : _openPdfExternal,
            icon: const Icon(Icons.open_in_new),
            label: const Text('เปิดด้วยแอปภายนอก'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: status == 'void' || _voiding ? null : _voidReceipt,
            icon: _voiding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cancel_outlined),
            label: Text(_voiding ? 'กำลังยกเลิก...' : 'ยกเลิกใบเสร็จ'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(title),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard() {
    final items = ((_receipt?['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('รายการ'),
            if (items.isEmpty)
              const Text('ไม่มีรายการ')
            else
              ...items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;

                final note = _safeTextOrEmpty(item['note']);

                return Container(
                  margin: EdgeInsets.only(
                    bottom: index == items.length - 1 ? 0 : 10,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safeText(item['description']),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'จำนวน',
                        value: _safeText(item['quantity']),
                      ),
                      _InfoRow(
                        label: 'ราคาต่อหน่วย',
                        value: '${_formatMoney(item['unitPrice'])} บาท',
                      ),
                      _InfoRow(
                        label: 'จำนวนเงิน',
                        value: '${_formatMoney(item['amount'])} บาท',
                      ),
                      _InfoRow(
                        label: 'หัก ณ ที่จ่าย',
                        value:
                            '${_formatMoney(item['withholdingTaxAmount'])} บาท',
                      ),
                      _InfoRow(
                        label: 'สุทธิ',
                        value: '${_formatMoney(item['netAmount'])} บาท',
                      ),
                      if (note.isNotEmpty)
                        _InfoRow(
                          label: 'หมายเหตุ',
                          value: note,
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long, size: 54, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      );
    }

    final receipt = _receipt ?? <String, dynamic>{};
    final clinicSnapshot =
        Map<String, dynamic>.from((receipt['clinicSnapshot'] as Map?) ?? {});
    final customerSnapshot =
        Map<String, dynamic>.from((receipt['customerSnapshot'] as Map?) ?? {});
    final paymentInfo =
        Map<String, dynamic>.from((receipt['paymentInfo'] as Map?) ?? {});

    final status = _safeTextOrEmpty(receipt['status']);
    final receiptNo = _safeText(receipt['receiptNo']);
    final pdfUrl = _safeTextOrEmpty(receipt['pdfUrl']);
    final pdfGeneratedAt = _formatIsoDate(receipt['pdfGeneratedAt']);
    final voidReason = _safeTextOrEmpty(receipt['voidReason']);
    final note = _safeTextOrEmpty(receipt['note']);
    final paymentMethod = _safeTextOrEmpty(paymentInfo['method']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 1.2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          receiptNo,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _buildStatusChip(status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'งวดบริการ',
                    value: _safeText(receipt['serviceMonth']),
                  ),
                  _InfoRow(
                    label: 'ช่วงบริการ',
                    value: _safeText(receipt['servicePeriodText']),
                  ),
                  _InfoRow(
                    label: 'วันที่ออก',
                    value: _formatIsoDate(receipt['issueDate']),
                  ),
                  if (note.isNotEmpty)
                    _InfoRow(
                      label: 'หมายเหตุ',
                      value: note,
                    ),
                  _InfoRow(
                    label: 'PDF',
                    value: pdfUrl.isNotEmpty ? 'มีแล้ว' : 'ยังไม่มี',
                  ),
                  _InfoRow(
                    label: 'สร้าง PDF เมื่อ',
                    value: pdfGeneratedAt,
                  ),
                  if (voidReason.isNotEmpty)
                    _InfoRow(
                      label: 'เหตุผลยกเลิก',
                      value: voidReason,
                    ),
                ],
              ),
            ),
          ),
          _buildInfoCard(
            title: 'ข้อมูลคลินิก',
            children: [
              _InfoRow(
                label: 'ชื่อคลินิก',
                value: _safeText(clinicSnapshot['clinicName']),
              ),
              _InfoRow(
                label: 'สาขา',
                value: _safeText(clinicSnapshot['clinicBranchName']),
              ),
              _InfoRow(
                label: 'ที่อยู่',
                value: _safeText(clinicSnapshot['clinicAddress']),
              ),
              _InfoRow(
                label: 'โทร',
                value: _safeText(clinicSnapshot['clinicPhone']),
              ),
              _InfoRow(
                label: 'เลขผู้เสียภาษี',
                value: _safeText(clinicSnapshot['clinicTaxId']),
              ),
              _InfoRow(
                label: 'เลขผู้หักภาษี',
                value: _safeText(clinicSnapshot['withholderTaxId']),
              ),
            ],
          ),
          _buildInfoCard(
            title: 'ข้อมูลลูกค้า',
            children: [
              _InfoRow(
                label: 'ชื่อลูกค้า',
                value: _safeText(customerSnapshot['customerName']),
              ),
              _InfoRow(
                label: 'ที่อยู่',
                value: _safeText(customerSnapshot['customerAddress']),
              ),
              _InfoRow(
                label: 'เลขผู้เสียภาษี',
                value: _safeText(customerSnapshot['customerTaxId']),
              ),
              _InfoRow(
                label: 'สาขา',
                value: _safeText(customerSnapshot['customerBranch']),
              ),
            ],
          ),
          _buildItemsCard(),
          _buildInfoCard(
            title: 'สรุปยอด',
            children: [
              _InfoRow(
                label: 'Subtotal',
                value: '${_formatMoney(receipt['subtotal'])} บาท',
              ),
              _InfoRow(
                label: 'หัก ณ ที่จ่าย',
                value: '${_formatMoney(receipt['withholdingTax'])} บาท',
              ),
              _InfoRow(
                label: 'ยอดสุทธิ',
                value: '${_formatMoney(receipt['netAmount'])} บาท',
              ),
              _InfoRow(
                label: 'จำนวนเงิน (ข้อความ)',
                value: _safeText(receipt['amountInThaiText']),
              ),
            ],
          ),
          _buildInfoCard(
            title: 'การชำระเงิน',
            children: [
              _InfoRow(
                label: 'วิธีชำระ',
                value: _paymentMethodLabel(paymentMethod),
              ),
              _InfoRow(
                label: 'ธนาคาร',
                value: _safeText(paymentInfo['bankName']),
              ),
              _InfoRow(
                label: 'ชื่อบัญชี',
                value: _safeText(paymentInfo['accountName']),
              ),
              _InfoRow(
                label: 'เลขบัญชี',
                value: _safeText(paymentInfo['accountNumber']),
              ),
              if (paymentMethod == 'cheque')
                _InfoRow(
                  label: 'เลขที่เช็ค',
                  value: _safeText(paymentInfo['chequeNo']),
                ),
              if (paymentMethod != 'cheque')
                _InfoRow(
                  label: 'อ้างอิง',
                  value: _safeText(paymentInfo['transferRef']),
                ),
              _InfoRow(
                label: 'Paid At',
                value: _formatIsoDate(paymentInfo['paidAt']),
              ),
              if (_safeTextOrEmpty(paymentInfo['note']).isNotEmpty)
                _InfoRow(
                  label: 'หมายเหตุ',
                  value: _safeText(paymentInfo['note']),
                ),
            ],
          ),
          _buildInfoCard(
            title: 'การทำรายการ',
            children: [
              _InfoRow(
                label: 'สร้างโดย',
                value: _safeText(receipt['createdByUserId']),
              ),
              _InfoRow(
                label: 'อัปเดตโดย',
                value: _safeText(receipt['updatedByUserId']),
              ),
              _InfoRow(
                label: 'สร้างเมื่อ',
                value: _formatIsoDate(receipt['createdAt']),
              ),
              _InfoRow(
                label: 'อัปเดตเมื่อ',
                value: _formatIsoDate(receipt['updatedAt']),
              ),
            ],
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 1.2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _buildActionButtons(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receiptNo = _safeText(
      _receipt?['receiptNo'],
      fallback: 'รายละเอียดใบเสร็จ',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(receiptNo),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _ReceiptPdfPreviewScreen extends StatelessWidget {
  final String title;
  final Uint8List pdfBytes;

  const _ReceiptPdfPreviewScreen({
    required this.title,
    required this.pdfBytes,
  });

  @override
  Widget build(BuildContext context) {
    final fileName =
        title.toLowerCase().endsWith('.pdf') ? title : '$title.pdf';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: () async {
              await Printing.sharePdf(
                bytes: pdfBytes,
                filename: fileName,
              );
            },
            icon: const Icon(Icons.share),
            tooltip: 'แชร์ PDF',
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        allowPrinting: true,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: fileName,
      ),
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
            width: 110,
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