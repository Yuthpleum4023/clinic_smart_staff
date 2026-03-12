import 'package:flutter/material.dart';

class PayslipCard extends StatelessWidget {
  final bool loading;
  final String errText;
  final List<String> months;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpenMonth;

  const PayslipCard({
    super.key,
    required this.loading,
    required this.errText,
    required this.months,
    required this.onRetry,
    required this.onOpenMonth,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'กำลังโหลดสลิป...',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (errText.isNotEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'สลิปเงินเดือน',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                errText,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองใหม่'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สลิปเงินเดือน',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              months.isEmpty ? 'ยังไม่มีงวดที่ปิด' : 'เลือกงวดที่ต้องการดูสลิป',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            if (months.isEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('รีเฟรช'),
                ),
              )
            else
              Column(
                children: months.take(6).map((m) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('งวด $m'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpenMonth(m),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}