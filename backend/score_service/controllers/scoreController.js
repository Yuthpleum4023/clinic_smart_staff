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

function syncIdentity(doc, identity = {}) {
  if (!doc) return false;

  let changed = false;

  const next = {
    userId: normStr(identity.userId),
    principalId: normStr(identity.principalId),
    fullName: normStr(identity.fullName),
    name: normStr(identity.name),
    phone: normStr(identity.phone),
    role: normStr(identity.role || "helper") || "helper",
  };

  const fields = ["userId", "principalId", "fullName", "name", "phone", "role"];

  for (const key of fields) {
    const incoming = next[key];
    const current = normStr(doc[key]);

    if (incoming && incoming !== current) {
      doc[key] = incoming;
      changed = true;
    }
  }

  if (!normStr(doc.role)) {
    doc.role = "helper";
    changed = true;
  }

  return changed;
}

function buildScoreResponse(doc) {
  return {
    ok: true,
    staffId: normStr(doc.staffId),
    clinicId: normStr(doc.clinicId),

    // ✅ marketplace identity
    userId: normStr(doc.userId),
    principalId: normStr(doc.principalId),
    fullName: normStr(doc.fullName),
    name: normStr(doc.name),
    phone: normStr(doc.phone),
    role: normStr(doc.role || "helper"),

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

async function findOrCreateTrustScore({ staffId, clinicId, identity = {} }) {
  const safeClinicId = normStr(clinicId || "global") || "global";

  let doc = await TrustScore.findOne({ staffId, clinicId: safeClinicId });

  if (!doc) {
    doc = await TrustScore.create({
      staffId,
      clinicId: safeClinicId,

      // ✅ identity snapshot for helper marketplace
      userId: normStr(identity.userId),
      principalId: normStr(identity.principalId),
      fullName: normStr(identity.fullName),
      name: normStr(identity.name),
      phone: normStr(identity.phone),
      role: normStr(identity.role || "helper") || "helper",

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

  if (doc.clinicId === undefined || doc.clinicId === null || !normStr(doc.clinicId)) {
    doc.clinicId = safeClinicId;
    changed = true;
  }

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

  // ✅ ensure new identity fields exist
  if (doc.userId === undefined || doc.userId === null) {
    doc.userId = "";
    changed = true;
  }

  if (doc.principalId === undefined || doc.principalId === null) {
    doc.principalId = "";
    changed = true;
  }

  if (doc.fullName === undefined || doc.fullName === null) {
    doc.fullName = "";
    changed = true;
  }

  if (doc.name === undefined || doc.name === null) {
    doc.name = "";
    changed = true;
  }

  if (doc.phone === undefined || doc.phone === null) {
    doc.phone = "";
    changed = true;
  }

  if (doc.role === undefined || doc.role === null || !normStr(doc.role)) {
    doc.role = "helper";
    changed = true;
  }

  if (syncIdentity(doc, identity)) {
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
    const clinicId = normStr(req.query.clinicId || req.user?.clinicId || "global") || "global";

    if (!staffId) {
      return res.status(400).json({ message: "staffId is required" });
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
    const clinicId = normStr(req.body?.clinicId || "global") || "global";
    const staffId = normStr(req.body?.staffId);
    const shiftId = normStr(req.body?.shiftId);
    const status = normalizeStatus(req.body?.status);
    const minutesLate = toNum(req.body?.minutesLate, 0);

    // ✅ optional identity snapshot for marketplace
    const identity = {
      userId: req.body?.userId,
      principalId: req.body?.principalId,
      fullName: req.body?.fullName,
      name: req.body?.name,
      phone: req.body?.phone,
      role: req.body?.role,
    };

    if (!staffId) {
      return res.status(400).json({ message: "staffId is required" });
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

    const doc = await findOrCreateTrustScore({
      staffId,
      clinicId,
      identity,
    });

    // ✅ sync identity again in case existing doc received new snapshot now
    syncIdentity(doc, identity);

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