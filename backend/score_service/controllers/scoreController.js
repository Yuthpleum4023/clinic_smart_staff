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

function normStr(v) {
  return String(v || "").trim();
}

function toNum(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function normalizeStatus(status) {
  let st = String(status || "").trim().toLowerCase();
  if (st === "cancelled") st = "cancelled_early";
  return st;
}

function ensureStringArray(v) {
  if (!Array.isArray(v)) return [];
  return v.map((x) => String(x || "").trim()).filter(Boolean);
}

function deriveLevel(score) {
  const s = clamp(toNum(score, BASE_SCORE), 0, 100);

  if (s >= 90) {
    return { level: "excellent", levelLabel: "ยอดเยี่ยม" };
  }
  if (s >= 80) {
    return { level: "good", levelLabel: "ดี" };
  }
  if (s >= 60) {
    return { level: "normal", levelLabel: "ปกติ" };
  }
  return { level: "risk", levelLabel: "เสี่ยง" };
}

function applyDerivedFields(doc) {
  const derived = deriveLevel(doc.trustScore);

  doc.level = derived.level;
  doc.levelLabel = derived.levelLabel;
  doc.levelUpdatedAt = new Date();

  doc.flags = ensureStringArray(doc.flags);
  doc.badges = ensureStringArray(doc.badges);

  return doc;
}

function buildScoreResponse(doc) {
  return {
    ok: true,
    staffId: normStr(doc.staffId),
    clinicId: normStr(doc.clinicId),

    trustScore: toNum(doc.trustScore, BASE_SCORE),

    level: normStr(doc.level || "unknown"),
    levelLabel: normStr(doc.levelLabel || "ยังไม่มีข้อมูล"),
    levelUpdatedAt: doc.levelUpdatedAt || null,

    flags: ensureStringArray(doc.flags),
    badges: ensureStringArray(doc.badges),

    stats: {
      totalShifts: toNum(doc.totalShifts, 0),
      completed: toNum(doc.completed, 0),
      late: toNum(doc.late, 0),
      noShow: toNum(doc.noShow, 0),
      cancelled: toNum(doc.cancelledEarly, 0),
    },

    meta: {
      createdAt: doc.createdAt || null,
      updatedAt: doc.updatedAt || null,
      lastNoShowAt: doc.lastNoShowAt || null,
    },
  };
}

async function findOrCreateTrustScore({ staffId, clinicId }) {
  let doc = await TrustScore.findOne({ staffId, clinicId });

  if (!doc) {
    doc = await TrustScore.create({
      staffId,
      clinicId,
      trustScore: BASE_SCORE,
      totalShifts: 0,
      completed: 0,
      late: 0,
      noShow: 0,
      cancelledEarly: 0,
      flags: [],
      badges: [],
    });

    applyDerivedFields(doc);
    await doc.save();
    return doc;
  }

  let changed = false;

  if (doc.trustScore === undefined || doc.trustScore === null) {
    doc.trustScore = BASE_SCORE;
    changed = true;
  }

  if (doc.totalShifts === undefined || doc.totalShifts === null) {
    doc.totalShifts = 0;
    changed = true;
  }

  if (doc.completed === undefined || doc.completed === null) {
    doc.completed = 0;
    changed = true;
  }

  if (doc.late === undefined || doc.late === null) {
    doc.late = 0;
    changed = true;
  }

  if (doc.noShow === undefined || doc.noShow === null) {
    doc.noShow = 0;
    changed = true;
  }

  if (doc.cancelledEarly === undefined || doc.cancelledEarly === null) {
    doc.cancelledEarly = 0;
    changed = true;
  }

  if (!Array.isArray(doc.flags)) {
    doc.flags = [];
    changed = true;
  }

  if (!Array.isArray(doc.badges)) {
    doc.badges = [];
    changed = true;
  }

  const prevLevel = normStr(doc.level);
  const prevLevelLabel = normStr(doc.levelLabel);
  applyDerivedFields(doc);

  if (
    prevLevel !== normStr(doc.level) ||
    prevLevelLabel !== normStr(doc.levelLabel)
  ) {
    changed = true;
  }

  if (changed) {
    await doc.save();
  }

  return doc;
}

// ----------------------------------------------------
// GET /score/staff/:staffId/score
// ----------------------------------------------------
async function getStaffScore(req, res) {
  try {
    const staffId = normStr(req.params.staffId);
    const clinicId = normStr(req.query.clinicId || req.user?.clinicId);

    if (!staffId) {
      return res.status(400).json({ message: "staffId is required" });
    }

    if (!clinicId) {
      return res.status(400).json({ message: "clinicId is required" });
    }

    const doc = await findOrCreateTrustScore({ staffId, clinicId });

    return res.json(buildScoreResponse(doc));
  } catch (e) {
    return res.status(500).json({
      message: "getStaffScore failed",
      error: e.message || String(e),
    });
  }
}

// ----------------------------------------------------
// POST /events/attendance
// body: { clinicId, staffId, shiftId, status, minutesLate }
// ----------------------------------------------------
async function postAttendanceEvent(req, res) {
  try {
    const clinicId = normStr(req.body?.clinicId);
    const staffId = normStr(req.body?.staffId);
    const shiftId = normStr(req.body?.shiftId);
    const status = normalizeStatus(req.body?.status);
    const minutesLate = toNum(req.body?.minutesLate, 0);

    if (!staffId) {
      return res.status(400).json({ message: "staffId is required" });
    }

    if (!clinicId) {
      return res.status(400).json({ message: "clinicId is required" });
    }

    if (!Object.prototype.hasOwnProperty.call(SCORE_RULES, status)) {
      return res.status(400).json({
        message: "Invalid status",
        allowed: Object.keys(SCORE_RULES),
      });
    }

    await AttendanceEvent.create({
      clinicId,
      staffId,
      shiftId,
      status,
      minutesLate,
      occurredAt: new Date(),
    });

    const doc = await findOrCreateTrustScore({ staffId, clinicId });

    const delta = SCORE_RULES[status];
    doc.trustScore = clamp(toNum(doc.trustScore, BASE_SCORE) + delta, 0, 100);
    doc.totalShifts = toNum(doc.totalShifts, 0) + 1;

    if (status === "completed") {
      doc.completed = toNum(doc.completed, 0) + 1;
    }

    if (status === "late") {
      doc.late = toNum(doc.late, 0) + 1;
    }

    if (status === "no_show") {
      doc.noShow = toNum(doc.noShow, 0) + 1;
      doc.lastNoShowAt = new Date();

      const flags = new Set(ensureStringArray(doc.flags));
      flags.add("NO_SHOW_30D");
      doc.flags = Array.from(flags);
    }

    if (status === "cancelled_early") {
      doc.cancelledEarly = toNum(doc.cancelledEarly, 0) + 1;
    }

    applyDerivedFields(doc);
    await doc.save();

    return res.json(buildScoreResponse(doc));
  } catch (e) {
    return res.status(500).json({
      message: "postAttendanceEvent failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  getStaffScore,
  postAttendanceEvent,
};