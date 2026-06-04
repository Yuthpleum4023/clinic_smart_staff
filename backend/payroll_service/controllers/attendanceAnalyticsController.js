const AttendanceSession = require("../models/AttendanceSession");
const {
  getEmployeeByStaffIdInternalOnly,
  getEmployeeByUserIdInternalOnly,
} = require("../utils/staffClient");

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


function bearerTokenFromReq(req) {
  const h = s(req.headers?.authorization || req.headers?.Authorization);
  return h.replace(/^Bearer\s+/i, "").trim();
}

function roleLabelFromEmploymentType(v) {
  const x = s(v).toLowerCase();
  if (["parttime", "part_time", "part-time", "helper"].includes(x)) {
    return "พาร์ทไทม์/ผู้ช่วย";
  }
  if (["fulltime", "full_time", "full-time", "employee"].includes(x)) {
    return "พนักงานประจำ";
  }
  return "";
}

function displayNameFromEmployee(emp) {
  return s(
    emp?.fullName ||
      emp?.name ||
      emp?.displayName ||
      emp?.employeeName ||
      emp?.userName
  );
}

function employeeCodeFromEmployee(emp) {
  return s(emp?.employeeCode || emp?.code || emp?.staffCode || emp?.staffId);
}

function authUserServiceBaseUrl() {
  return s(
    process.env.AUTH_USER_SERVICE_URL ||
      process.env.AUTH_SERVICE_URL ||
      "https://auth-user-service-afwu.onrender.com"
  ).replace(/\/+$/, "");
}

function authorizationHeaderFromToken(bearerToken = "") {
  const t = s(bearerToken);
  if (!t) return "";
  return /^Bearer\s+/i.test(t) ? t : `Bearer ${t}`;
}

async function getHelperProfileByUserIdForAnalytics(userId, bearerToken = "") {
  const uid = s(userId);
  if (!uid) return null;

  const base = authUserServiceBaseUrl();
  if (!base) return null;

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);

  try {
    const headers = { Accept: "application/json" };
    const authHeader = authorizationHeaderFromToken(bearerToken);
    if (authHeader) headers.Authorization = authHeader;

    const url = `${base}/helpers/by-userid/${encodeURIComponent(uid)}`;

    const res = await fetch(url, {
      method: "GET",
      headers,
      signal: ctrl.signal,
    });

    const raw = await res.text();
    let data = null;

    try {
      data = raw ? JSON.parse(raw) : null;
    } catch (_) {
      data = null;
    }

    if (res.status === 404) return null;

    if (!res.ok) {
      if (process.env.DEBUG_ATTENDANCE_ANALYTICS === "true") {
        console.warn("⚠️ helper profile lookup failed:", {
          userId: uid.slice(0, 8),
          status: res.status,
          message: data?.message || raw?.slice(0, 120) || "",
        });
      }
      return null;
    }

    const helper =
      data?.helper ||
      data?.data?.helper ||
      data?.data ||
      data?.user ||
      data;

    const fullName = s(
      helper?.fullName ||
        helper?.name ||
        helper?.displayName ||
        helper?.userName
    );

    if (!fullName) return null;

    return {
      userId: s(helper?.userId) || uid,
      staffId: s(helper?.staffId),
      fullName,
      name: fullName,
      displayName: fullName,
      employmentType: "helper",
      role: "helper",
    };
  } catch (e) {
    if (process.env.DEBUG_ATTENDANCE_ANALYTICS === "true") {
      console.warn("⚠️ helper profile lookup error:", {
        userId: uid.slice(0, 8),
        message: e?.message || String(e),
      });
    }
    return null;
  } finally {
    clearTimeout(timer);
  }
}


const ANALYTICS_PERSON_CACHE = new Map();
const ANALYTICS_PERSON_CACHE_TTL_MS = 30 * 60 * 1000;

function analyticsPersonCacheKeys({ clinicId = "", principalId = "", staffId = "", userId = "" } = {}) {
  const c = s(clinicId) || "no-clinic";
  return [principalId, staffId, userId]
    .map(s)
    .filter(Boolean)
    .map((v) => `${c}:${v}`);
}

function getAnalyticsPersonCache(ctx = {}) {
  const now = Date.now();

  for (const key of analyticsPersonCacheKeys(ctx)) {
    const hit = ANALYTICS_PERSON_CACHE.get(key);

    if (!hit) continue;

    if (hit.expiresAt <= now) {
      ANALYTICS_PERSON_CACHE.delete(key);
      continue;
    }

    return hit.emp || null;
  }

  return null;
}

function setAnalyticsPersonCache(ctx = {}, emp = null) {
  const displayName = displayNameFromEmployee(emp);
  if (!displayName) return;

  const employeeCode = employeeCodeFromEmployee(emp);
  const cachedEmp = {
    ...(emp || {}),
    displayName,
    fullName: displayName,
    name: displayName,
    employeeCode,
  };

  const value = {
    emp: cachedEmp,
    expiresAt: Date.now() + ANALYTICS_PERSON_CACHE_TTL_MS,
  };

  for (const key of analyticsPersonCacheKeys(ctx)) {
    ANALYTICS_PERSON_CACHE.set(key, value);
  }
}

function warnAnalyticsLookupFailed(source, e, { principalId = "", staffId = "", userId = "" } = {}) {
  console.warn("⚠️ enrichTopRiskStaff lookup failed:", {
    source,
    principalId,
    staffId,
    userId,
    status: e?.status || null,
    message: e?.message || String(e),
  });
}


async function enrichTopRiskStaff(topRiskStaff, req) {
  const token = bearerTokenFromReq(req);
  const clinicId = String(
    req?.user?.clinicId || req?.clinicId || req?.query?.clinicId || req?.body?.clinicId || ""
  ).trim();

  return Promise.all(
    topRiskStaff.map(async (item) => {
      const principalId = s(item.principalId);
      const staffId = s(item.staffId);
      const userId = s(item.userId);

      const cacheCtx = { clinicId, principalId, staffId, userId };
      let emp = getAnalyticsPersonCache(cacheCtx);

      if (!emp && staffId) {
        try {
          emp = await getEmployeeByStaffIdInternalOnly(staffId, token, { clinicId });
        } catch (e) {
          warnAnalyticsLookupFailed("staff_service.by_staff", e, {
            principalId,
            staffId,
            userId,
          });
        }
      }

      if (!emp && userId) {
        try {
          emp = await getEmployeeByUserIdInternalOnly(userId, token, { clinicId });
        } catch (e) {
          warnAnalyticsLookupFailed("staff_service.by_user", e, {
            principalId,
            staffId,
            userId,
          });
        }
      }

      if (!emp && userId) {
        emp = await getHelperProfileByUserIdForAnalytics(userId, token);
      }

      if (emp) {
        setAnalyticsPersonCache(cacheCtx, emp);
      } else {
        emp = getAnalyticsPersonCache(cacheCtx);
      }

      const displayName = displayNameFromEmployee(emp);
      const employeeCode = employeeCodeFromEmployee(emp);
      const roleLabel =
        roleLabelFromEmploymentType(emp?.employmentType) ||
        (staffId ? "พนักงาน" : "ผู้ช่วย");
      const resolved = !!displayName;

      return {
        ...item,
        principalId,
        staffId,
        userId,
        displayName,
        employeeCode,
        roleLabel,
        nameStatus: resolved ? "resolved" : "pending",
        canResolveName: !resolved && !!(staffId || userId),
      };
    })
  );
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
        staffId: s(session.staffId),
        userId: s(session.userId),
        sessions: 0,
        riskScore: 0,
        abnormal: 0,
      };
    }

    if (!staffRiskMap[principalId].staffId && s(session.staffId)) {
      staffRiskMap[principalId].staffId = s(session.staffId);
    }

    if (!staffRiskMap[principalId].userId && s(session.userId)) {
      staffRiskMap[principalId].userId = s(session.userId);
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


async function resolveAnalyticsName(req, res) {
  try {
    const token = bearerTokenFromReq(req);
    const clinicId = String(
      req?.user?.clinicId || req?.clinicId || req?.query?.clinicId || req?.body?.clinicId || ""
    ).trim();

    const principalId = s(req?.query?.principalId || req?.body?.principalId);
    const rawStaffId = s(req?.query?.staffId || req?.body?.staffId);
    const rawUserId = s(req?.query?.userId || req?.body?.userId);

    const staffId = rawStaffId || (principalId && !principalId.startsWith("usr_") ? principalId : "");
    const userId = rawUserId || (principalId && principalId.startsWith("usr_") ? principalId : "");

    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        nameStatus: "pending",
        canResolveName: false,
        message: "clinicId required",
      });
    }

    if (!staffId && !userId) {
      return res.status(400).json({
        ok: false,
        nameStatus: "pending",
        canResolveName: false,
        message: "staffId or userId required",
      });
    }

    const cacheCtx = { clinicId, principalId, staffId, userId };
    let emp = getAnalyticsPersonCache(cacheCtx);
    const errors = [];

    if (!emp && staffId) {
      try {
        emp = await getEmployeeByStaffIdInternalOnly(staffId, token, { clinicId });
      } catch (e) {
        errors.push({
          source: "staff_service.by_staff",
          status: e?.status || null,
          message: e?.message || String(e),
        });
      }
    }

    if (!emp && userId) {
      try {
        emp = await getEmployeeByUserIdInternalOnly(userId, token, { clinicId });
      } catch (e) {
        errors.push({
          source: "staff_service.by_user",
          status: e?.status || null,
          message: e?.message || String(e),
        });
      }
    }

    if (!emp && userId) {
      emp = await getHelperProfileByUserIdForAnalytics(userId, token);
    }

    if (emp) {
      setAnalyticsPersonCache(cacheCtx, emp);
    } else {
      emp = getAnalyticsPersonCache(cacheCtx);
    }

    const displayName = displayNameFromEmployee(emp);
    const employeeCode = employeeCodeFromEmployee(emp);
    const roleLabel =
      roleLabelFromEmploymentType(emp?.employmentType) ||
      (staffId ? "พนักงาน" : "ผู้ช่วย");

    const resolved = !!displayName;

    return res.status(resolved ? 200 : 202).json({
      ok: true,
      displayName: displayName || "",
      employeeCode: employeeCode || "",
      roleLabel,
      nameStatus: resolved ? "resolved" : "pending",
      canResolveName: !!(staffId || userId),
      principalId,
      staffId,
      userId,
      debug:
        process.env.DEBUG_ATTENDANCE_ANALYTICS === "true"
          ? { errors }
          : undefined,
    });
  } catch (err) {
    console.error("resolveAnalyticsName error:", err);
    return res.status(500).json({
      ok: false,
      displayName: "",
      nameStatus: "pending",
      canResolveName: true,
      message: err?.message || "resolve name failed",
    });
  }
}


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
    const enrichedTopRiskStaff = await enrichTopRiskStaff(topRiskStaff, req);

    if (process.env.DEBUG_ATTENDANCE_ANALYTICS === "true") {
      const withName = enrichedTopRiskStaff.filter((x) => s(x.displayName)).length;
      const withoutName = enrichedTopRiskStaff.length - withName;

      console.log("[ATT_ANALYTICS][ENRICH_TOP_RISK]", {
        clinicId,
        month,
        total: enrichedTopRiskStaff.length,
        withName,
        withoutName,
        items: enrichedTopRiskStaff.map((x) => ({
          principalId: s(x.principalId).slice(0, 8),
          staffId: s(x.staffId).slice(0, 8),
          userId: s(x.userId).slice(0, 8),
          hasName: !!s(x.displayName),
          roleLabel: s(x.roleLabel),
        })),
      });
    }

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
      topRiskStaff: enrichedTopRiskStaff,
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
  resolveAnalyticsName,
  clinicAnalytics,
  staffAnalytics,
};