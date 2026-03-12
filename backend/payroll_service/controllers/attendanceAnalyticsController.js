// backend/payroll_service/controllers/attendanceAnalyticsController.js

const AttendanceSession = require("../models/AttendanceSession");

function s(v) {
  return String(v || "").trim();
}

function isYm(v) {
  return /^\d{4}-\d{2}$/.test(s(v));
}

function monthFromQuery(q) {
  const m = s(q.month);
  if (isYm(m)) return m;

  const now = new Date();
  const y = now.getFullYear();
  const mo = String(now.getMonth() + 1).padStart(2, "0");
  return `${y}-${mo}`;
}

function monthRange(month) {
  const start = new Date(`${month}-01T00:00:00`);
  const end = new Date(start);
  end.setMonth(end.getMonth() + 1);
  return { start, end };
}

// =====================================================
// CLINIC ANALYTICS
// =====================================================

async function clinicAnalytics(req, res) {
  try {
    const clinicId = req.userCtx?.clinicId || req.user?.clinicId;
    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        message: "clinicId missing",
      });
    }

    const month = monthFromQuery(req.query);
    const { start, end } = monthRange(month);

    const match = {
      clinicId,
      checkInAt: { $gte: start, $lt: end },
    };

    const sessions = await AttendanceSession.find(match).lean();

    let totalSessions = 0;
    let lateCount = 0;
    let earlyLeaveCount = 0;
    let abnormalCount = 0;
    let suspiciousCount = 0;
    let totalOtMinutes = 0;
    let totalWorkedMinutes = 0;

    const staffRisk = {};

    for (const s of sessions) {
      totalSessions++;

      if (s.lateMinutes > 0) lateCount++;

      if (s.leftEarly) earlyLeaveCount++;

      if (s.abnormal) abnormalCount++;

      if (Array.isArray(s.suspiciousFlags) && s.suspiciousFlags.length > 0) {
        suspiciousCount++;
      }

      totalOtMinutes += s.otMinutes || 0;
      totalWorkedMinutes += s.workedMinutes || 0;

      const pid = s.principalId || "unknown";

      if (!staffRisk[pid]) {
        staffRisk[pid] = {
          principalId: pid,
          sessions: 0,
          riskScore: 0,
          abnormal: 0,
        };
      }

      staffRisk[pid].sessions += 1;
      staffRisk[pid].riskScore += s.riskScore || 0;

      if (s.abnormal) {
        staffRisk[pid].abnormal += 1;
      }
    }

    const attendanceRate =
      totalSessions > 0
        ? Number(((totalSessions - abnormalCount) / totalSessions).toFixed(2))
        : 1;

    const topRisk = Object.values(staffRisk)
      .sort((a, b) => b.riskScore - a.riskScore)
      .slice(0, 5);

    return res.json({
      ok: true,
      clinicId,
      month,
      summary: {
        totalSessions,
        lateCount,
        earlyLeaveCount,
        abnormalCount,
        suspiciousCount,
        totalOtMinutes,
        totalWorkedMinutes,
        attendanceRate,
      },
      topRiskStaff: topRisk,
    });
  } catch (err) {
    console.error("clinicAnalytics error:", err);
    return res.status(500).json({
      ok: false,
      message: "analytics failed",
    });
  }
}

// =====================================================
// STAFF ANALYTICS
// =====================================================

async function staffAnalytics(req, res) {
  try {
    const clinicId = req.userCtx?.clinicId || req.user?.clinicId;
    const principalId = s(req.params.principalId);

    if (!clinicId || !principalId) {
      return res.status(400).json({
        ok: false,
        message: "principalId required",
      });
    }

    const month = monthFromQuery(req.query);
    const { start, end } = monthRange(month);

    const sessions = await AttendanceSession.find({
      clinicId,
      principalId,
      checkInAt: { $gte: start, $lt: end },
    }).lean();

    let totalSessions = 0;
    let lateCount = 0;
    let earlyLeaveCount = 0;
    let abnormalCount = 0;
    let suspiciousCount = 0;
    let totalOtMinutes = 0;
    let totalWorkedMinutes = 0;
    let riskScore = 0;

    for (const s of sessions) {
      totalSessions++;

      if (s.lateMinutes > 0) lateCount++;

      if (s.leftEarly) earlyLeaveCount++;

      if (s.abnormal) abnormalCount++;

      if (Array.isArray(s.suspiciousFlags) && s.suspiciousFlags.length > 0) {
        suspiciousCount++;
      }

      totalOtMinutes += s.otMinutes || 0;
      totalWorkedMinutes += s.workedMinutes || 0;
      riskScore += s.riskScore || 0;
    }

    const attendanceRate =
      totalSessions > 0
        ? Number(((totalSessions - abnormalCount) / totalSessions).toFixed(2))
        : 1;

    return res.json({
      ok: true,
      clinicId,
      principalId,
      month,
      summary: {
        totalSessions,
        lateCount,
        earlyLeaveCount,
        abnormalCount,
        suspiciousCount,
        totalOtMinutes,
        totalWorkedMinutes,
        attendanceRate,
        riskScore,
      },
    });
  } catch (err) {
    console.error("staffAnalytics error:", err);
    return res.status(500).json({
      ok: false,
      message: "analytics failed",
    });
  }
}

module.exports = {
  clinicAnalytics,
  staffAnalytics,
};