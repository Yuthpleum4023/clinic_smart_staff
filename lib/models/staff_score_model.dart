class StaffScoreStats {
  final int totalShifts;
  final int completed;
  final int late;
  final int noShow;
  final int cancelled;

  const StaffScoreStats({
    required this.totalShifts,
    required this.completed,
    required this.late,
    required this.noShow,
    required this.cancelled,
  });

  factory StaffScoreStats.fromMap(Map<String, dynamic> map) {
    int _toInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

    return StaffScoreStats(
      totalShifts: _toInt(map['totalShifts']),
      completed: _toInt(map['completed']),
      late: _toInt(map['late']),
      noShow: _toInt(map['noShow']),
      cancelled: _toInt(map['cancelled']),
    );
  }
}

class StaffScore {
  final String staffId;
  final double trustScore;
  final List<String> flags;
  final List<String> badges;
  final StaffScoreStats stats;

  const StaffScore({
    required this.staffId,
    required this.trustScore,
    required this.flags,
    required this.badges,
    required this.stats,
  });

  factory StaffScore.fromMap(Map<String, dynamic> map) {
    double _toDouble(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

    final statsMap = (map['stats'] is Map<String, dynamic>)
        ? (map['stats'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final flagsRaw = map['flags'];
    final badgesRaw = map['badges'];

    return StaffScore(
      staffId: (map['staffId'] ?? '').toString(),
      trustScore: _toDouble(map['trustScore']),
      flags: (flagsRaw is List) ? flagsRaw.map((e) => e.toString()).toList() : const [],
      badges: (badgesRaw is List) ? badgesRaw.map((e) => e.toString()).toList() : const [],
      stats: StaffScoreStats.fromMap(statsMap),
    );
  }

  String get level {
    // กำหนดระดับแบบง่าย (ปรับได้)
    if (trustScore >= 90) return 'Gold';
    if (trustScore >= 80) return 'Silver';
    if (trustScore >= 70) return 'Bronze';
    return 'Risk';
  }
}
