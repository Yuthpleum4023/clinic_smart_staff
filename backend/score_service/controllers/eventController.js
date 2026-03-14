// controllers/eventController.js
const AttendanceEvent = require("../models/AttendanceEvent");
const TrustScore = require("../models/TrustScore");

const BASE_SCORE = 80;

// ✅ IMPORTANT: schema บังคับ cancelled_early (ไม่ใช่ cancelled)
const SCORE_RULES = {
  completed: +1,
  late: -2,
  cancelled_early: -5,
  no_show: -25,
};

// ✅ IMPORTANT: allow cancelled_early
const ALLOWED_STATUSES = ["completed", "late", "no_show", "cancelled_early"];

function clamp(n, a, b) {
  return Math.max(a, Math.min(b, n));
}

function normStr(v) {
  return String(v || "").trim();
}

function normStatus(s) {
  return String(s || "").trim().toLowerCase();
}

// ✅ backward-compatible aliases -> normalize to schema value
function normalizeIncomingStatus(s) {
  const v = normStatus(s);

  if (v === "cancelled" || v === "cancel" || v === "canceled") {
    return "cancelled_early";
  }
  if (v === "canceled_early" || v === "cancel_early") {
    return "cancelled_early";
  }

  return v;
}

// ======================================================
// ✅ score -> level
// ======================================================
function scoreToLevel(score) {
  const s = Number(score || 0);

  if (s >= 90) return { level: "excellent", label: "ยอดเยี่ยม" };
  if (s >= 75) return { level: "good", label: "ดีมาก" };
  if (s >= 60) return { level: "normal", label: "ปกติ" };
  return { level: "risk", label: "เสี่ยง" };
}

function updateLevel(scoreDoc) {
  const { level, label } = scoreToLevel(scoreDoc.trustScore);
  scoreDoc.level = level;
  scoreDoc.levelLabel = label;
  scoreDoc.levelUpdatedAt = new Date();
  return scoreDoc;
}

// ✅ NEW: sync helper identity snapshot for marketplace
function syncIdentity(scoreDoc, identity = {}) {
  if (!scoreDoc) return scoreDoc;

  const userId = normStr(identity.userId);
  const principalId = normStr(identity.principalId);
  const fullName = normStr(identity.fullName);
  const name = normStr(identity.name);
  const phone = normStr(identity.phone);
  const role = normStr(identity.role);

  if (userId) scoreDoc.userId = userId;
  if (principalId) scoreDoc.principalId = principalId;
  if (fullName) scoreDoc.fullName = fullName;
  if (name) scoreDoc.name = name;
  if (phone) scoreDoc.phone = phone;
  if (role) scoreDoc.role = role;

  return scoreDoc;
}

function ensureScoreDefaults(scoreDoc, clinicId = "") {
  scoreDoc.staffId = normStr(scoreDoc.staffId);
  scoreDoc.clinicId = normStr(scoreDoc.clinicId || clinicId);

  // ✅ NEW: marketplace identity defaults
  scoreDoc.userId = normStr(scoreDoc.userId);
  scoreDoc.principalId = normStr(scoreDoc.principalId);
  scoreDoc.fullName = normStr(scoreDoc.fullName);
  scoreDoc.name = normStr(scoreDoc.name);
  scoreDoc.phone = normStr(scoreDoc.phone);
  scoreDoc.role = normStr(scoreDoc.role || "helper") || "helper";

  scoreDoc.totalShifts = Number(scoreDoc.totalShifts || 0);
  scoreDoc.completed = Number(scoreDoc.completed || 0);
  scoreDoc.late = Number(scoreDoc.late || 0);
  scoreDoc.noShow = Number(scoreDoc.noShow || 0);
  scoreDoc.cancelledEarly = Number(scoreDoc.cancelledEarly || 0);

  scoreDoc.flags = Array.isArray(scoreDoc.flags) ? scoreDoc.flags : [];
  scoreDoc.badges = Array.isArray(scoreDoc.badges) ? scoreDoc.badges : [];

  if (typeof scoreDoc.trustScore !== "number") {
    scoreDoc.trustScore = BASE_SCORE;
  }

  scoreDoc.level = normStr(scoreDoc.level || "unknown") || "unknown";
  scoreDoc.levelLabel =
    normStr(scoreDoc.levelLabel || "ยังไม่มีข้อมูล") || "ยังไม่มีข้อมูล";
  scoreDoc.levelUpdatedAt = scoreDoc.levelUpdatedAt || null;
  scoreDoc.lastNoShowAt = scoreDoc.lastNoShowAt || null;

  updateLevel(scoreDoc);

  return scoreDoc;
}

function applyRules(scoreDoc, { status, minutesLate, occurredAt }) {
  ensureScoreDefaults(scoreDoc, scoreDoc.clinicId);

  const delta = SCORE_RULES[status] ?? 0;

  // ✅ late extra penalty (optional MVP rule)
  let finalDelta = delta;
  if (status === "late" && Number(minutesLate || 0) > 30) {
    finalDelta -= 1;
  }

  scoreDoc.totalShifts += 1;

  if (status === "completed") scoreDoc.completed += 1;
  if (status === "late") scoreDoc.late += 1;
  if (status === "cancelled_early") scoreDoc.cancelledEarly += 1;

  if (status === "no_show") {
    scoreDoc.noShow += 1;
    scoreDoc.lastNoShowAt = occurredAt;

    const flags = new Set(scoreDoc.flags);
    flags.add("NO_SHOW_30D");
    scoreDoc.flags = Array.from(flags);
  }

  scoreDoc.trustScore = clamp(scoreDoc.trustScore + finalDelta, 0, 100);

  // ✅ badges (simple MVP)
  const badges = new Set(scoreDoc.badges);
  const highlyReliable = scoreDoc.noShow === 0 && scoreDoc.totalShifts >= 10;

  if (highlyReliable) {
    badges.add("HIGHLY_RELIABLE");
  } else {
    badges.delete("HIGHLY_RELIABLE");
  }

  scoreDoc.badges = Array.from(badges);

  updateLevel(scoreDoc);

  return { scoreDoc, delta: finalDelta };
}

// ✅ POST /events/attendance
async function postAttendanceEvent(req, res) {
  try {
    // ✅ Allow either:
    // - Internal service call (X-Internal-Key -> middleware sets req.internal=true)
    // - Admin/system JWT
    const role = normStr(req.user?.role).toLowerCase();
    const isInternal = req.internal === true || role === "system";

    if (!(isInternal || role === "admin" || role === "clinic_admin")) {
      return res.status(403).json({ message: "Forbidden" });
    }

    const body = req.body || {};

    const clinicId = normStr(body.clinicId || req.user?.clinicId);
    const staffId = normStr(body.staffId);
    const shiftId = normStr(body.shiftId);
    const status = body.status;
    const minutesLate = Number(body.minutesLate || 0);
    const occurredAt = body.occurredAt;

    // ✅ NEW: identity snapshot (optional, but important for marketplace)
    const identity = {
      userId: body.userId,
      principalId: body.principalId,
      fullName: body.fullName,
      name: body.name,
      phone: body.phone,
      role: body.role,
    };

    if (!clinicId || !staffId || !status || !occurredAt) {
      return res.status(400).json({
        message: "clinicId, staffId, status, occurredAt required",
        got: { clinicId, staffId, status, occurredAt },
        allowed: ALLOWED_STATUSES,
      });
    }

    const st = normalizeIncomingStatus(status);

    if (!ALLOWED_STATUSES.includes(st)) {
      return res.status(400).json({
        message: "Invalid status",
        allowed: ALLOWED_STATUSES,
        got: status,
        normalized: st,
      });
    }

    const occ = new Date(occurredAt);
    if (Number.isNaN(occ.getTime())) {
      return res.status(400).json({ message: "occurredAt is invalid date" });
    }

    // ✅ save event
    const event = await AttendanceEvent.create({
      clinicId,
      staffId,
      shiftId,
      status: st,
      minutesLate,
      occurredAt: occ,
    });

    // ✅ SaaS FIX: find by clinicId + staffId
    let scoreDoc = await TrustScore.findOne({ staffId, clinicId });

    // ✅ auto create by clinic + staff
    if (!scoreDoc) {
      scoreDoc = await TrustScore.create({
        staffId,
        clinicId,

        // ✅ NEW identity snapshot
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
        lastNoShowAt: null,
        flags: [],
        badges: [],
        level: "unknown",
        levelLabel: "ยังไม่มีข้อมูล",
        levelUpdatedAt: new Date(),
      });
    }

    ensureScoreDefaults(scoreDoc, clinicId);

    // ✅ NEW: keep old docs updated when new identity comes in
    syncIdentity(scoreDoc, identity);

    const { delta } = applyRules(scoreDoc, {
      status: st,
      minutesLate,
      occurredAt: occ,
    });

    await scoreDoc.save();

    return res.json({
      ok: true,
      applied: {
        clinicId,
        staffId,
        status: st,
        delta,
      },
      event,
      score: {
        staffId: scoreDoc.staffId,
        clinicId: scoreDoc.clinicId,

        // ✅ NEW identity fields
        userId: scoreDoc.userId || "",
        principalId: scoreDoc.principalId || "",
        fullName: scoreDoc.fullName || "",
        name: scoreDoc.name || "",
        phone: scoreDoc.phone || "",
        role: scoreDoc.role || "helper",

        trustScore: scoreDoc.trustScore,
        totalShifts: scoreDoc.totalShifts,
        completed: scoreDoc.completed,
        late: scoreDoc.late,
        noShow: scoreDoc.noShow,
        cancelledEarly: scoreDoc.cancelledEarly,
        level: scoreDoc.level,
        levelLabel: scoreDoc.levelLabel,
        levelUpdatedAt: scoreDoc.levelUpdatedAt,
        lastNoShowAt: scoreDoc.lastNoShowAt,
        flags: scoreDoc.flags || [],
        badges: scoreDoc.badges || [],
      },
    });
  } catch (e) {
    // ✅ duplicate key guard for unique {staffId, clinicId}
    if (e && e.code === 11000) {
      return res.status(409).json({
        message: "TrustScore for this clinic/staff already exists",
        error: e.message || String(e),
      });
    }

    return res.status(500).json({
      message: "postAttendanceEvent failed",
      error: e.message || String(e),
    });
  }
}

module.exports = { postAttendanceEvent };