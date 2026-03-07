// lib/widgets/apply_success_dialog.dart
//
// ✅ Apply Success Animation Dialog
// - ใช้ได้ทุกหน้า
// - Auto close
// - ไม่มี dependency เพิ่ม
//

import 'package:flutter/material.dart';

Future<void> showApplySuccessDialog(BuildContext context) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return const _ApplySuccessContent();
    },
  );
}

class _ApplySuccessContent extends StatefulWidget {
  const _ApplySuccessContent();

  @override
  State<_ApplySuccessContent> createState() => _ApplySuccessContentState();
}

class _ApplySuccessContentState extends State<_ApplySuccessContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _controller.forward();

    _autoClose();
  }

  Future<void> _autoClose() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: const Icon(
                Icons.check_circle,
                size: 90,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'สมัครงานสำเร็จ',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'คลินิกจะติดต่อกลับหากผ่านการพิจารณา',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}