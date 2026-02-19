import 'package:flutter/material.dart';
import 'package:clinic_smart_staff/services/score_service.dart';
import 'package:clinic_smart_staff/models/staff_score_model.dart';

class StaffTrustScoreCard extends StatefulWidget {
  final String staffId;
  final String? title;

  const StaffTrustScoreCard({
    super.key,
    required this.staffId,
    this.title,
  });

  @override
  State<StaffTrustScoreCard> createState() => _StaffTrustScoreCardState();
}

class _StaffTrustScoreCardState extends State<StaffTrustScoreCard> {
  late Future<StaffScore> _future;

  @override
  void initState() {
    super.initState();
    _future = ScoreService.getStaffScore(widget.staffId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StaffScore>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('กำลังโหลด Trust Score...'),
                ],
              ),
            ),
          );
        }

        if (snap.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title ?? 'Trust Score',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'โหลดคะแนนไม่สำเร็จ: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _future =
                          ScoreService.getStaffScore(widget.staffId);
                    }),
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            ),
          );
        }

        final s = snap.data!;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title ?? 'Trust Score',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Text(
                      '⭐ ${s.trustScore.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        s.level,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Text('งานทั้งหมด: ${s.stats.totalShifts}'),
                Text(
                  'สำเร็จ: ${s.stats.completed} • '
                  'สาย: ${s.stats.late} • '
                  'No-show: ${s.stats.noShow} • '
                  'ยกเลิก: ${s.stats.cancelled}',
                ),

                if (s.flags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Flags: ${s.flags.join(", ")}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
