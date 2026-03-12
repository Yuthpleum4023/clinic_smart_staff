import 'package:flutter/material.dart';

class PremiumGateCard extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final String title;
  final String subtitle;
  final VoidCallback onUpgrade;

  const PremiumGateCard({
    super.key,
    required this.loading,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onUpgrade,
  });

  Widget _premiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Text(
        'Premium',
        style: TextStyle(
          color: Colors.amber.shade800,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Card(
        elevation: 0.8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.amber.shade100),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'กำลังตรวจสอบสิทธิ์ Premium...',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _premiumBadge(),
            ],
          ),
        ),
      );
    }

    if (enabled) return const SizedBox.shrink();

    return Card(
      elevation: 0.8,
      color: const Color(0xFFFFFEFB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.amber.shade100),
      ),
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
                    title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _premiumBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium,
                      size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ปลดล็อกฟีเจอร์บันทึกเวลางานด้วยลายนิ้วมือ',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpgrade,
                icon: const Icon(Icons.lock_open),
                label: const Text('อัปเกรด Premium • 299 บาท'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}