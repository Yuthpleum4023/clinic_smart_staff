import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:clinic_smart_staff/api/clinic_logo_api.dart';
import 'package:clinic_smart_staff/widgets/clinic_logo_view.dart';

class ClinicLogoManagementScreen extends StatefulWidget {
  final String clinicId;
  final String initialClinicName;
  final String initialLogoUrl;

  const ClinicLogoManagementScreen({
    super.key,
    required this.clinicId,
    required this.initialClinicName,
    this.initialLogoUrl = '',
  });

  @override
  State<ClinicLogoManagementScreen> createState() =>
      _ClinicLogoManagementScreenState();
}

class _ClinicLogoManagementScreenState
    extends State<ClinicLogoManagementScreen> {
  final ImagePicker _picker = ImagePicker();

  bool _uploading = false;
  bool _removing = false;

  String _clinicName = '';
  String _logoUrl = '';

  @override
  void initState() {
    super.initState();
    _clinicName = widget.initialClinicName.trim();
    _logoUrl = widget.initialLogoUrl.trim();
  }

  bool get _busy => _uploading || _removing;

  Future<void> _pickAndUpload() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );

      if (picked == null) return;

      setState(() {
        _uploading = true;
      });

      final result = await ClinicLogoApi.uploadLogo(
        clinicId: widget.clinicId,
        file: File(picked.path),
      );

      final clinic = (result['clinic'] is Map<String, dynamic>)
          ? result['clinic'] as Map<String, dynamic>
          : <String, dynamic>{};

      setState(() {
        _logoUrl = (clinic['logoUrl'] ?? '').toString().trim();
        final nextName = (clinic['name'] ?? '').toString().trim();
        if (nextName.isNotEmpty) {
          _clinicName = nextName;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปโหลดโลโก้สำเร็จ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปโหลดโลโก้ไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  Future<void> _removeLogo() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('ลบโลโก้คลินิก'),
              content: const Text('ยืนยันการลบโลโก้ใช่หรือไม่'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('ลบโลโก้'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      setState(() {
        _removing = true;
      });

      final result = await ClinicLogoApi.removeLogo(
        clinicId: widget.clinicId,
      );

      final clinic = (result['clinic'] is Map<String, dynamic>)
          ? result['clinic'] as Map<String, dynamic>
          : <String, dynamic>{};

      setState(() {
        _logoUrl = '';
        final nextName = (clinic['name'] ?? '').toString().trim();
        if (nextName.isNotEmpty) {
          _clinicName = nextName;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบโลโก้สำเร็จ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบโลโก้ไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _removing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicName = _clinicName.trim();
    final logoUrl = _logoUrl.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการโลโก้คลินิก'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 10,
                  color: Color(0x08000000),
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                ClinicLogoView(
                  logoUrl: logoUrl,
                  clinicName: clinicName,
                  size: 108,
                ),
                const SizedBox(height: 16),
                Text(
                  clinicName.isNotEmpty ? clinicName : 'คลินิก',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  logoUrl.isNotEmpty
                      ? 'มีโลโก้อัปโหลดแล้ว'
                      : 'ยังไม่มีโลโก้ ระบบจะแสดง fallback อัตโนมัติ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'คำแนะนำ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'รองรับไฟล์ PNG, JPG, JPEG, WEBP ขนาดไม่เกิน 5 MB',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'เมื่ออัปโหลดแล้ว โลโก้นี้สามารถนำไปใช้ในหน้าแอปและเอกสาร PDF ของคลินิกได้',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _busy ? null : _pickAndUpload,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_outlined),
            label: Text(_uploading ? 'กำลังอัปโหลด...' : 'เลือกรูปและอัปโหลด'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy || logoUrl.isEmpty ? null : _removeLogo,
            icon: _removing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            label: Text(_removing ? 'กำลังลบ...' : 'ลบโลโก้'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}