// lib/models/trust_score_model.dart
class TrustScoreStats {
  final int totalShifts;
  final int completed;
  final int late;
  final int noShow;
  final int cancelled;

  const TrustScoreStats({
    required this.totalShifts,
    required this.completed,
    required this.late,
    required this.noShow,
    required this.cancelled,
  });

  factory TrustScoreStats.fromMap(Map<String, dynamic> map) {
    return TrustScoreStats(
      totalShifts: (map['totalShifts'] as num? ?? 0).toInt(),
      completed: (map['completed'] as num? ?? 0).toInt(),
      late: (map['late'] as num? ?? 0).toInt(),
      noShow: (map['noShow'] as num? ?? 0).toInt(),
      cancelled: (map['cancelled'] as num? ?? 0).toInt(),
    );
  }
}

class TrustScoreModel {
  final String staffId;
  final double trustScore; // 0-100
  final List<String> flags;
  final List<String> badges;
  final TrustScoreStats stats;

  const TrustScoreModel({
    required this.staffId,
    required this.trustScore,
    required this.flags,
    required this.badges,
    required this.stats,
  });

  factory TrustScoreModel.fromMap(Map<String, dynamic> map) {
    return TrustScoreModel(
      staffId: (map['staffId'] ?? '').toString(),
      trustScore: (map['trustScore'] as num? ?? 0).toDouble(),
      flags: (map['flags'] as List? ?? []).map((e) => e.toString()).toList(),
      badges: (map['badges'] as List? ?? []).map((e) => e.toString()).toList(),
      stats: TrustScoreStats.fromMap(
        Map<String, dynamic>.from(map['stats'] as Map? ?? {}),
      ),
    );
  }

  bool get hasNoShowFlag => flags.contains('NO_SHOW_30D');

  String get topBadge {
    if (badges.isNotEmpty) return badges.first;
    if (trustScore >= 90) return 'HIGHLY_RELIABLE';
    if (trustScore >= 80) return 'RELIABLE';
    if (trustScore >= 70) return 'OK';
    return 'RISKY';
  }
}
