const AttendanceSession = require("../models/AttendanceSession");

function s(v) {
  return String(v || "").trim();
}

function isYm(v) {
  return /^\d{4}-\d{2}$/.test(s(v));
}

function monthFromQuery(query) {
  const month = s(query.month);
  if (isYm(month)) return month;

  const now = new Date();
  const year = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  return `${year}-${mm}`;
}

function monthRange(month) {
  const start = new Date(`${month}-01T00:00:00.000Z`);
  const end = new Date(start);
  end.setMonth(end.getMonth() + 1);
  return { start, end };
}

function safeNumber(value) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n : 0;
}

function buildSummaryFromSessions(sessions) {
  let totalSessions = 0;
  let lateCount = 0;
  let earlyLeaveCount = 0;
  let abnormalCount = 0;
  let suspiciousCount = 0;
  let totalOtMinutes = 0;
  let totalWorkedMinutes = 0;
  let totalRiskScore = 0;

  const staffRiskMap = {};

  for (const session of sessions) {
    totalSessions += 1;

    if (safeNumber(session.lateMinutes) > 0) {
      lateCount += 1;
    }

    if (session.leftEarly === true) {
      earlyLeaveCount += 1;
    }

    if (session.abnormal === true) {
      abnormalCount += 1;
    }

    if (
      Array.isArray(session.suspiciousFlags) &&
      session.suspiciousFlags.length > 0
    ) {
      suspiciousCount += 1;
    }

    totalOtMinutes += safeNumber(session.otMinutes);
    totalWorkedMinutes += safeNumber(session.workedMinutes);
    totalRiskScore += safeNumber(session.riskScore);

    const principalId = s(session.principalId) || "unknown";

    if (!staffRiskMap[principalId]) {
      staffRiskMap[principalId] = {
        principalId,
        sessions: 0,
        riskScore: 0,
        abnormal: 0,
      };
    }

    staffRiskMap[principalId].sessions += 1;
    staffRiskMap[principalId].riskScore += safeNumber(session.riskScore);

    if (session.abnormal === true) {
      staffRiskMap[principalId].abnormal += 1;
    }
  }

  const attendanceRate =
    totalSessions > 0
      ? Number(((totalSessions - abnormalCount) / totalSessions).toFixed(2))
      : 1;

  const topRiskStaff = Object.values(staffRiskMap)
    .sort((a, b) => safeNumber(b.riskScore) - safeNumber(a.riskScore))
    .slice(0, 5);

  return {
    summary: {
      totalSessions,
      lateCount,
      earlyLeaveCount,
      abnormalCount,
      suspiciousCount,
      totalOtMinutes,
      totalWorkedMinutes,
      attendanceRate,
      riskScore: totalRiskScore,
    },
    topRiskStaff,
  };
}

// =====================================================
// CLINIC ANALYTICS
// =====================================================

async function clinicAnalytics(req, res) {
  try {
    const clinicId = s(req.userCtx?.clinicId || req.user?.clinicId);

    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        message: "clinicId missing",
      });
    }

    const month = monthFromQuery(req.query);
    const { start, end } = monthRange(month);

    const sessions = await AttendanceSession.find({
      clinicId,
      checkInAt: { $gte: start, $lt: end },
    }).lean();

    const { summary, topRiskStaff } = buildSummaryFromSessions(sessions);

    return res.json({
      ok: true,
      clinicId,
      month,
      summary: {
        totalSessions: summary.totalSessions,
        lateCount: summary.lateCount,
        earlyLeaveCount: summary.earlyLeaveCount,
        abnormalCount: summary.abnormalCount,
        suspiciousCount: summary.suspiciousCount,
        totalOtMinutes: summary.totalOtMinutes,
        totalWorkedMinutes: summary.totalWorkedMinutes,
        attendanceRate: summary.attendanceRate,
      },
      topRiskStaff,
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
    const clinicId = s(req.userCtx?.clinicId || req.user?.clinicId);
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

    const { summary } = buildSummaryFromSessions(sessions);

    return res.json({
      ok: true,
      clinicId,
      principalId,
      month,
      summary: {
        totalSessions: summary.totalSessions,
        lateCount: summary.lateCount,
        earlyLeaveCount: summary.earlyLeaveCount,
        abnormalCount: summary.abnormalCount,
        suspiciousCount: summary.suspiciousCount,
        totalOtMinutes: summary.totalOtMinutes,
        totalWorkedMinutes: summary.totalWorkedMinutes,
        attendanceRate: summary.attendanceRate,
        riskScore: summary.riskScore,
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