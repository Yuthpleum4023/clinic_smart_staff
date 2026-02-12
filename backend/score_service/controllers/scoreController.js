const TrustScore = require("../models/TrustScore");
const AttendanceEvent = require("../models/AttendanceEvent");

const BASE_SCORE = 80;

// ✅ key มาตรฐาน
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

  // ✅ backward compat: ถ้ามี client ส่ง cancelled มา ให้ map เป็น cancelled_early
  if (st === "cancelled") st = "cancelled_early";

  return st;
}

// --------------------------------------
// GET /staff/:staffId/score
// --------------------------------------
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
        cancelled: doc.cancelled || 0, // ✅ คงชื่อเดิมให้ UI ใช้ได้เลย
      },
    });
  } catch (e) {
    return res.status(500).json({
      message: "getStaffScore failed",
      error: e.message || String(e),
    });
  }
}

// --------------------------------------
// POST /events/attendance
// --------------------------------------
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

    // 1) log event
    await AttendanceEvent.create({
      clinicId,
      staffId: sId,
      shiftId,
      status: st,
      minutesLate: Number(minutesLate || 0),
      occurredAt: new Date(),
    });

    // 2) load/create TrustScore
    let doc = await TrustScore.findOne({ staffId: sId });
    if (!doc) doc = await TrustScore.create({ staffId: sId, trustScore: BASE_SCORE });

    // 3) apply score
    const delta = SCORE_RULES[st];
    doc.trustScore = clamp((doc.trustScore ?? BASE_SCORE) + delta, 0, 100);

    // 4) counters
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
      applied: { status: st, delta },
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

module.exports = { getStaffScore, postAttendanceEvent };
