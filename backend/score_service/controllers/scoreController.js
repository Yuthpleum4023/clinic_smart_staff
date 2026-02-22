const TrustScore = require("../models/TrustScore");
const AttendanceEvent = require("../models/AttendanceEvent");

const BASE_SCORE = 80;

const SCORE_RULES = {
  completed: +1,
  late: -2,
  cancelled_early: -5,
  no_show: -25,
};

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

function normalizeStatus(status) {
  let st = String(status || "").trim().toLowerCase();
  if (st === "cancelled") st = "cancelled_early";
  return st;
}

// ----------------------------------------------------
// GET /staff/:staffId/score
// ----------------------------------------------------
async function getStaffScore(req, res) {
  try {
    const staffId = (req.params.staffId || "").trim();
    if (!staffId) return res.status(400).json({ message: "staffId is required" });

    let doc = await TrustScore.findOne({ staffId }).lean();

    if (!doc) {
      const created = await TrustScore.create({ staffId, trustScore: BASE_SCORE });
      doc = created.toObject();
    }

    return res.json({
      staffId: doc.staffId,
      trustScore: doc.trustScore,
      flags: doc.flags || [],
      badges: doc.badges || [],
      stats: {
        totalShifts: doc.totalShifts || 0,
        completed: doc.completed || 0,
        late: doc.late || 0,
        noShow: doc.noShow || 0,
        cancelled: doc.cancelled || 0,
      },
    });
  } catch (e) {
    return res.status(500).json({
      message: "getStaffScore failed",
      error: e.message || String(e),
    });
  }
}

// ----------------------------------------------------
// ✅ GET /staff/search?q=...
// REAL FIX → Proxy ไป auth_user_service
// ----------------------------------------------------
async function searchStaff(req, res) {
  try {
    const q = String(req.query.q || "").trim();
    const limit = Math.max(1, Math.min(Number(req.query.limit || 20), 50));

    if (!q) {
      return res.status(400).json({ message: "q is required" });
    }

    const authBase =
      process.env.AUTH_USER_SERVICE_URL ||
      "https://auth-user-service-afwu.onrender.com";

    const internalKey = process.env.INTERNAL_KEY;

    const r = await fetch(
      `${authBase}/staff/search?q=${encodeURIComponent(q)}&limit=${limit}`,
      {
        headers: {
          "Content-Type": "application/json",
          ...(internalKey ? { "X-Internal-Key": internalKey } : {}),
          ...(req.headers.authorization
            ? { Authorization: req.headers.authorization }
            : {}),
        },
      }
    );

    const data = await r.json();

    if (!r.ok) {
      return res.status(r.status).json(data);
    }

    const items = data.items || [];

    // ✅ เติม trustScore ให้ UI เลือกง่ายขึ้น
    const staffIds = items
      .map((i) => String(i.staffId || "").trim())
      .filter(Boolean);

    const scoreDocs = staffIds.length
      ? await TrustScore.find({ staffId: { $in: staffIds } })
          .select("staffId trustScore totalShifts completed late noShow cancelled flags badges")
          .lean()
      : [];

    const scoreMap = new Map(scoreDocs.map((d) => [d.staffId, d]));

    const results = items.map((u) => {
      const sc = scoreMap.get(u.staffId);

      return {
        ...u,

        trustScore: sc ? sc.trustScore : null,
        stats: sc
          ? {
              totalShifts: sc.totalShifts || 0,
              completed: sc.completed || 0,
              late: sc.late || 0,
              noShow: sc.noShow || 0,
              cancelled: sc.cancelled || 0,
            }
          : null,
      };
    });

    return res.json({
      ok: true,
      q,
      count: results.length,
      results,
    });
  } catch (e) {
    return res.status(500).json({
      message: "searchStaff failed",
      error: e.message || String(e),
    });
  }
}

// ----------------------------------------------------
// POST /events/attendance
// ----------------------------------------------------
async function postAttendanceEvent(req, res) {
  try {
    const { clinicId = "", staffId = "", shiftId = "", status, minutesLate = 0 } = req.body || {};

    const sId = String(staffId || "").trim();
    if (!sId) return res.status(400).json({ message: "staffId is required" });

    const st = normalizeStatus(status);
    if (!Object.prototype.hasOwnProperty.call(SCORE_RULES, st)) {
      return res.status(400).json({
        message: "Invalid status",
        allowed: Object.keys(SCORE_RULES),
      });
    }

    await AttendanceEvent.create({
      clinicId,
      staffId: sId,
      shiftId,
      status: st,
      minutesLate: Number(minutesLate || 0),
      occurredAt: new Date(),
    });

    let doc = await TrustScore.findOne({ staffId: sId });
    if (!doc) doc = await TrustScore.create({ staffId: sId, trustScore: BASE_SCORE });

    const delta = SCORE_RULES[st];
    doc.trustScore = clamp((doc.trustScore ?? BASE_SCORE) + delta, 0, 100);

    doc.totalShifts = (doc.totalShifts || 0) + 1;

    if (st === "completed") doc.completed = (doc.completed || 0) + 1;
    if (st === "late") doc.late = (doc.late || 0) + 1;

    if (st === "no_show") {
      doc.noShow = (doc.noShow || 0) + 1;
      doc.lastNoShowAt = new Date();
      if (!doc.flags.includes("NO_SHOW_30D")) doc.flags.push("NO_SHOW_30D");
    }

    if (st === "cancelled_early") {
      doc.cancelled = (doc.cancelled || 0) + 1;
    }

    await doc.save();

    return res.json({
      ok: true,
      staffId: doc.staffId,
      trustScore: doc.trustScore,
      stats: {
        totalShifts: doc.totalShifts,
        completed: doc.completed,
        late: doc.late,
        noShow: doc.noShow,
        cancelled: doc.cancelled,
      },
      flags: doc.flags,
      badges: doc.badges || [],
    });
  } catch (e) {
    return res.status(500).json({
      message: "postAttendanceEvent failed",
      error: e.message || String(e),
    });
  }
}

module.exports = { getStaffScore, postAttendanceEvent, searchStaff };