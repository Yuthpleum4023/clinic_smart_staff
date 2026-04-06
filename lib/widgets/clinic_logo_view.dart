import 'package:flutter/material.dart';

/// =======================================================
/// ClinicLogoView
/// -------------------------------------------------------
/// - ใช้แสดงโลโก้คลินิกจาก URL
/// - ถ้าไม่มี logoUrl → แสดง fallback เป็นตัวอักษรชื่อคลินิก
/// - รองรับ error loading (เช่น URL เสีย)
/// - ใช้ซ้ำได้ทุกหน้า (header / profile / receipt)
/// =======================================================
class ClinicLogoView extends StatelessWidget {
  final String logoUrl;
  final String clinicName;
  final double size;

  const ClinicLogoView({
    super.key,
    required this.logoUrl,
    required this.clinicName,
    this.size = 72,
  });

  String _initial() {
    final name = clinicName.trim();
    if (name.isEmpty) return 'C';
    return name.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = logoUrl.trim();

    // ------------------------------
    // ❌ ไม่มีโลโก้ → fallback
    // ------------------------------
    if (url.isEmpty) {
      return _fallback();
    }

    // ------------------------------
    // ✅ มีโลโก้ → โหลดจาก network
    // ------------------------------
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,

        // loading state
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _loading();
        },

        // error state
        errorBuilder: (context, error, stackTrace) {
          return _fallback();
        },
      ),
    );
  }

  // ------------------------------
  // ⏳ Loading UI
  // ------------------------------
  Widget _loading() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: SizedBox(
        width: size * 0.35,
        height: size * 0.35,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  // ------------------------------
  // 🔁 Fallback UI (ไม่มีโลโก้)
  // ------------------------------
  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(
        _initial(),
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.bold,
          color: Colors.orange.shade700,
        ),
      ),
    );
  }
}