import 'package:flutter/material.dart';

class AttendanceCard extends StatelessWidget {
  final String title;
  final String statusLine;
  final String errText;
  final bool loading; // โหลดสถานะวันนี้
  final bool posting; // กำลังส่ง check-in / check-out
  final bool bioLoading; // กำลังสแกนนิ้ว
  final bool checkedIn;
  final bool checkedOut;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback onRefresh;
  final VoidCallback onOpenHistory;

  const AttendanceCard({
    super.key,
    required this.title,
    required this.statusLine,
    required this.errText,
    required this.loading,
    required this.posting,
    required this.bioLoading,
    required this.checkedIn,
    required this.checkedOut,
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onRefresh,
    required this.onOpenHistory,
  });

  bool get _canCheckIn =>
      !bioLoading && !posting && !checkedIn && !checkedOut;

  bool get _canCheckOut =>
      !bioLoading && !posting && checkedIn && !checkedOut;

  bool get _isBusyAction => bioLoading || posting;

  bool get _isRefreshingOnly => loading && !posting && !bioLoading;

  String get _helperText {
    if (bioLoading) return 'กำลังยืนยันลายนิ้วมือ...';
    if (posting) return 'กำลังบันทึกข้อมูล...';
    if (checkedOut) return 'วันนี้เช็คเอาท์เรียบร้อยแล้ว';
    if (checkedIn) return 'เช็คอินแล้ว สามารถกดเช็คเอาท์ได้';
    return 'พร้อมเช็คอินสำหรับวันนี้';
  }

  String get _badgeText {
    if (errText.isNotEmpty) return 'มีปัญหา';
    if (bioLoading) return 'กำลังสแกน';
    if (posting) return 'กำลังบันทึก';
    if (checkedOut) return 'เสร็จสิ้น';
    if (checkedIn) return 'กำลังทำงาน';
    return 'พร้อมใช้งาน';
  }

  Color _badgeFg() {
    if (errText.isNotEmpty) return Colors.red.shade700;
    if (bioLoading || posting) return Colors.blueGrey.shade700;
    if (checkedOut) return Colors.green.shade700;
    if (checkedIn) return Colors.orange.shade800;
    return Colors.purple.shade700;
  }

  Color _badgeBg() {
    if (errText.isNotEmpty) return Colors.red.shade50;
    if (bioLoading || posting) return Colors.blueGrey.shade50;
    if (checkedOut) return Colors.green.shade50;
    if (checkedIn) return Colors.orange.shade50;
    return Colors.purple.shade50;
  }

  Color _cardBorderColor() {
    if (errText.isNotEmpty) return Colors.red.shade100;
    if (checkedIn && !checkedOut) return Colors.orange.shade200;
    if (checkedOut) return Colors.green.shade100;
    return Colors.purple.shade100;
  }

  Color _cardBgColor() {
    if (errText.isNotEmpty) return const Color(0xFFFFFBFB);
    if (checkedIn && !checkedOut) return const Color(0xFFFFFBF5);
    if (checkedOut) return const Color(0xFFFCFFFC);
    return Colors.white;
  }

  Widget _statusBadge() {
    final fg = _badgeFg();
    final bg = _badgeBg();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.15)),
      ),
      child: Text(
        _badgeText,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statusPanel() {
    if (errText.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
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
      );
    }

    if (_isBusyAction) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _helperText,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isRefreshingOnly) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                statusLine.isNotEmpty
                    ? '$statusLine • กำลังรีเฟรช'
                    : 'กำลังอัปเดตสถานะวันนี้...',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.grey.shade100,
      ),
      child: Text(
        statusLine.isNotEmpty ? statusLine : _helperText,
        style: TextStyle(
          color: Colors.grey.shade800,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.8,
      color: _cardBgColor(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: _cardBorderColor(),
          width: 1,
        ),
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
                _statusBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'ยืนยันตัวตนด้วยลายนิ้วมือ แล้วกดเช็คอินหรือเช็คเอาท์เพื่อบันทึกเวลาทำงาน',
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            _statusPanel(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _canCheckIn ? onCheckIn : null,
                    icon: _isBusyAction
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      checkedIn || checkedOut ? 'เช็คอินแล้ว' : 'เช็คอิน',
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _canCheckOut ? onCheckOut : null,
                    icon: _isBusyAction
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout),
                    label: Text(
                      checkedOut ? 'เช็คเอาท์แล้ว' : 'เช็คเอาท์',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: posting || bioLoading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      loading ? 'กำลังรีเฟรช...' : 'รีเฟรชสถานะวันนี้',
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: posting || bioLoading ? null : onOpenHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('ดูย้อนหลัง'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}