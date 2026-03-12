import 'package:flutter/material.dart';

class PolicyCard extends StatelessWidget {
  final bool loading;
  final String errText;
  final List<String> lines;
  final bool isHelper;
  final VoidCallback onRetry;

  const PolicyCard({
    super.key,
    required this.loading,
    required this.errText,
    required this.lines,
    required this.isHelper,
    required this.onRetry,
  });

  String get _subtitle {
    return isHelper
        ? 'สรุปกติกาที่เกี่ยวข้องกับผู้ช่วยและการลงเวลาทำงาน'
        : 'สรุปกติกาที่เกี่ยวข้องกับการลงเวลา การทำงาน และ OT';
  }

  Widget _headerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Text(
        'Policy',
        style: TextStyle(
          color: Colors.blueGrey.shade700,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _loadingCard() {
    return Card(
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.blueGrey.shade100),
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
                'กำลังโหลดกติกาของคลินิก...',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _headerBadge(),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Card(
      elevation: 0.8,
      color: const Color(0xFFFFFBFB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.red.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    'กติกาการทำงานของคลินิก',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _headerBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errText,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineItem(String line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              size: 14,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line,
              style: TextStyle(
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return _loadingCard();

    if (errText.isNotEmpty && lines.isEmpty) {
      return _errorCard();
    }

    if (lines.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0.8,
      color: const Color(0xFFFCFDFE),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.blueGrey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    'กติกาการทำงานของคลินิก',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _headerBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            ...lines.map(_lineItem),
          ],
        ),
      ),
    );
  }
}