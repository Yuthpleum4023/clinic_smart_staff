import 'package:clinic_smart_staff/services/location_engine.dart';
import 'package:clinic_smart_staff/services/settings_service.dart';

enum HelperSortMode {
  recommended,
  trustScore,
  distance,
  experience,
}

class HelperRecommendationResult {
  final Map<String, dynamic> helper;
  final double finalScore;
  final double trustScore;
  final double? distanceKm;
  final String nearbyLabel;
  final int totalShifts;
  final int completed;
  final int late;
  final int noShow;
  final List<String> reasons;
  final List<String> warnings;

  const HelperRecommendationResult({
    required this.helper,
    required this.finalScore,
    required this.trustScore,
    required this.distanceKm,
    required this.nearbyLabel,
    required this.totalShifts,
    required this.completed,
    required this.late,
    required this.noShow,
    required this.reasons,
    required this.warnings,
  });
}

class HelperRecommendationEngine {
  static String _s(dynamic v) => (v ?? '').toString().trim();

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static double _d(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  static Map<String, dynamic> _stats(Map<String, dynamic> item) {
    final raw = item['stats'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  static List<HelperRecommendationResult> rankHelpers({
    required List<Map<String, dynamic>> helpers,
    required AppLocation? clinicLocation,
    HelperSortMode sortMode = HelperSortMode.recommended,
  }) {
    final results = helpers
        .map(
          (helper) => _buildResult(
            helper: helper,
            clinicLocation: clinicLocation,
          ),
        )
        .toList();

    switch (sortMode) {
      case HelperSortMode.recommended:
        results.sort((a, b) => b.finalScore.compareTo(a.finalScore));
        break;
      case HelperSortMode.trustScore:
        results.sort((a, b) {
          final byTrust = b.trustScore.compareTo(a.trustScore);
          if (byTrust != 0) return byTrust;
          final aDist = a.distanceKm ?? 999999;
          final bDist = b.distanceKm ?? 999999;
          return aDist.compareTo(bDist);
        });
        break;
      case HelperSortMode.distance:
        results.sort((a, b) {
          final aDist = a.distanceKm ?? 999999;
          final bDist = b.distanceKm ?? 999999;
          final byDistance = aDist.compareTo(bDist);
          if (byDistance != 0) return byDistance;
          return b.trustScore.compareTo(a.trustScore);
        });
        break;
      case HelperSortMode.experience:
        results.sort((a, b) {
          final byExp = b.totalShifts.compareTo(a.totalShifts);
          if (byExp != 0) return byExp;
          return b.trustScore.compareTo(a.trustScore);
        });
        break;
    }

    return results;
  }

  static HelperRecommendationResult _buildResult({
    required Map<String, dynamic> helper,
    required AppLocation? clinicLocation,
  }) {
    final trustScoreRaw = _d(helper['trustScore']);
    final trustScore = trustScoreRaw > 0 ? trustScoreRaw : 80.0;

    final stats = _stats(helper);
    final completed = _i(stats['completed']);
    final late = _i(stats['late']);
    final noShow = _i(stats['noShow']);
    final totalShifts = _i(stats['totalShifts']);

    final distanceKm =
        LocationEngine.resolveDistanceKmForItem(helper, clinicLocation);
    final nearbyLabel =
        LocationEngine.resolveNearbyLabelForItem(helper, clinicLocation);

    double score = 0;
    final reasons = <String>[];
    final warnings = <String>[];

    // 1) Trust score (ตัวหลัก)
    score += trustScore * 0.55;

    // 2) Reliability จาก completion
    if (totalShifts > 0) {
      final completionRate = completed / totalShifts;
      score += completionRate * 20.0;

      if (completionRate >= 0.9) {
        reasons.add('อัตรางานสำเร็จสูง');
      } else if (completionRate < 0.6) {
        warnings.add('อัตรางานสำเร็จค่อนข้างต่ำ');
      }
    } else {
      warnings.add('ยังมีประวัติงานน้อย');
    }

    // 3) Distance
    if (distanceKm != null) {
      if (distanceKm <= 3) {
        score += 15;
        reasons.add('อยู่ใกล้คลินิกมาก');
      } else if (distanceKm <= 8) {
        score += 10;
        reasons.add('อยู่ค่อนข้างใกล้คลินิก');
      } else if (distanceKm <= 15) {
        score += 5;
      } else if (distanceKm > 25) {
        score -= 8;
        warnings.add('ระยะทางค่อนข้างไกล');
      }
    }

    // 4) Late / No-show
    if (late > 0) {
      score -= late * 1.5;
      if (late >= 3) {
        warnings.add('มีประวัติมาสาย');
      }
    }

    if (noShow > 0) {
      score -= noShow * 6.0;
      warnings.add('มีประวัติ no-show');
    }

    // 5) Experience
    if (totalShifts >= 20) {
      score += 5;
      reasons.add('มีประสบการณ์ทำงาน');
    } else if (totalShifts >= 10) {
      score += 2;
    }

    // 6) Labels
    if (nearbyLabel.isNotEmpty) {
      reasons.add(nearbyLabel);
    }

    if (trustScore >= 90) {
      reasons.add('Trust score ดีมาก');
    } else if (trustScore >= 80) {
      reasons.add('Trust score ดี');
    } else if (trustScore < 60) {
      warnings.add('Trust score ค่อนข้างต่ำ');
    }

    final finalScore = score.clamp(0.0, 100.0);

    return HelperRecommendationResult(
      helper: helper,
      finalScore: finalScore,
      trustScore: trustScore,
      distanceKm: distanceKm,
      nearbyLabel: nearbyLabel,
      totalShifts: totalShifts,
      completed: completed,
      late: late,
      noShow: noShow,
      reasons: reasons.toSet().toList(),
      warnings: warnings.toSet().toList(),
    );
  }
}