// lib/widgets/helper_trust_card.dart
import 'package:flutter/material.dart';
import 'package:clinic_payroll/models/trust_score_model.dart';

class HelperTrustCard extends StatelessWidget {
  final String staffId;
  final String staffName;
  final String role; // เช่น "ผู้ช่วยทันตแพทย์"
  final String? distanceText; // optional เช่น "2.4 km"
  final TrustScoreModel? trust; // ถ้ายังโหลดไม่เสร็จ ส่ง null
  final bool isLoading;
  final VoidCallback? onTap;

  const HelperTrustCard({
    super.key,
    required this.staffId,
    required this.staffName,
    required this.role,
    this.distanceText,
    this.trust,
    this.isLoading = false,
    this.onTap,
  });

  Color _trustColor(double s) {
    if (s >= 85) return Colors.green;
    if (s >= 70) return Colors.orange;
    return Colors.red;
  }

  String _badgeLabel(String b) {
    switch (b) {
      case 'HIGHLY_RELIABLE':
        return 'เชื่อถือสูงมาก';
      case 'RELIABLE':
        return 'เชื่อถือสูง';
      case 'OK':
        return 'พอใช้';
      case 'RISKY':
        return 'เสี่ยง';
      default:
        return b.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = trust;
    final score = t?.trustScore ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                child: Text(
                  staffName.isNotEmpty ? staffName.trim()[0] : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staffName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            role,
                            style: TextStyle(color: Colors.grey.shade700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (distanceText != null) ...[
                          const SizedBox(width: 8),
                          Text('• $distanceText', style: TextStyle(color: Colors.grey.shade700)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (isLoading) ...[
                      const LinearProgressIndicator(minHeight: 6),
                    ] else if (t == null) ...[
                      Text('ยังไม่โหลดคะแนน', style: TextStyle(color: Colors.grey.shade600)),
                    ] else ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _trustColor(score).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: _trustColor(score).withOpacity(0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 16, color: _trustColor(score)),
                                const SizedBox(width: 6),
                                Text(
                                  score.toStringAsFixed(0),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _trustColor(score),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _badgeLabel(t.topBadge),
                                  style: TextStyle(color: Colors.grey.shade800),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          if (t.hasNoShowFlag)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.red.withOpacity(0.25)),
                              ),
                              child: const Text('⚠️ NO-SHOW 30D'),
                            ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Text(
                        'งานทั้งหมด ${t.stats.totalShifts} • ✅ ${t.stats.completed} • ⏰ ${t.stats.late} • ❌ ${t.stats.noShow}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
