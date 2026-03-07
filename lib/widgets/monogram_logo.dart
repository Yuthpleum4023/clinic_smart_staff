import 'package:flutter/material.dart';

class MonogramLogo extends StatelessWidget {
  final String abbr; // เช่น MC
  final String? hexColor; // เช่น #6D28D9 (optional)
  final double size;

  const MonogramLogo({
    super.key,
    required this.abbr,
    this.hexColor,
    this.size = 44,
  });

  Color _parseHex(String? hex) {
    final h = (hex ?? '').trim();
    if (h.isEmpty) return Colors.grey.shade200;

    final v = h.replaceAll('#', '');
    if (v.length == 6) {
      return Color(int.parse('FF$v', radix: 16));
    }
    if (v.length == 8) {
      return Color(int.parse(v, radix: 16));
    }
    return Colors.grey.shade200;
  }

  Color _textColor(Color bg) {
    // เลือกสีตัวอักษรให้ contrast แบบง่ายๆ
    final luminance = bg.computeLuminance();
    return luminance > 0.55 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final bg = _parseHex(hexColor);
    final fg = _textColor(bg);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Center(
        child: Text(
          abbr.trim().isEmpty ? 'CL' : abbr.trim().toUpperCase(),
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.38,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}