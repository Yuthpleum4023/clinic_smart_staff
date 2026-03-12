import 'package:flutter/material.dart';

class UrgentJobsCard extends StatelessWidget {
  final bool visible;
  final bool loading;
  final String errText;
  final int count;
  final String line;
  final bool isClinic;
  final VoidCallback onRefresh;
  final VoidCallback onOpenList;

  const UrgentJobsCard({
    super.key,
    required this.visible,
    required this.loading,
    required this.errText,
    required this.count,
    required this.line,
    required this.isClinic,
    required this.onRefresh,
    required this.onOpenList,
  });

  String get _title => isClinic ? 'ประกาศงานของคลินิก' : 'งานด่วนสำหรับผู้ช่วย';

  String get _subtitle => isClinic
      ? 'ติดตามประกาศงานที่เปิดอยู่และอัปเดตล่าสุดของคลินิก'
      : 'ติดตามงานด่วนที่เปิดรับและพร้อมสมัครได้ทันที';

  Widget _headerBadge({
    required String text,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
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
        side: BorderSide(color: Colors.orange.shade100),
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
                'กำลังอัปเดตข้อมูลล่าสุด...',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _headerBadge(
              text: 'Live',
              fg: Colors.orange.shade800,
              bg: Colors.orange.shade50,
              border: Colors.orange.shade200,
            ),
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
                Expanded(
                  child: Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _headerBadge(
                  text: 'มีปัญหา',
                  fg: Colors.red.shade700,
                  bg: Colors.red.shade50,
                  border: Colors.red.shade100,
                ),
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
            const SizedBox(height: 10),
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
                        fontSize: 12.5,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('ลองใหม่'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onOpenList,
                    icon: const Icon(Icons.list_alt),
                    label: const Text('ไปหน้ารายการ'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard() {
    return Card(
      elevation: 0.8,
      color: const Color(0xFFFEFEFE),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey.shade100,
              child: Icon(Icons.flash_on, color: Colors.grey.shade700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isClinic ? 'ตอนนี้ยังไม่มีประกาศงาน' : 'ตอนนี้ยังไม่มีงานด่วน',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isClinic
                        ? 'เมื่อมีการเปิดประกาศใหม่ ระบบจะแสดงในส่วนนี้'
                        : 'เมื่อมีงานที่เปิดรับใหม่ ระบบจะแสดงในส่วนนี้',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onOpenList,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('ไปดูรายการ'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeCard() {
    return Card(
      elevation: 0.8,
      color: const Color(0xFFFFFCF6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.orange.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.orange.shade50,
                  child: Icon(Icons.flash_on, color: Colors.orange.shade800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isClinic
                            ? 'ประกาศงานที่เปิดอยู่: $count งาน'
                            : 'งานด่วนที่เปิดอยู่: $count งาน',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _headerBadge(
                  text: 'อัปเดต',
                  fg: Colors.orange.shade800,
                  bg: Colors.orange.shade50,
                  border: Colors.orange.shade200,
                ),
              ],
            ),
            if (line.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade50),
                ),
                child: Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('รีเฟรช'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onOpenList,
                    icon: const Icon(Icons.list_alt),
                    label: const Text('ดูทั้งหมด'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    if (loading) return _loadingCard();
    if (errText.isNotEmpty) return _errorCard();
    if (count <= 0) return _emptyCard();
    return _activeCard();
  }
}