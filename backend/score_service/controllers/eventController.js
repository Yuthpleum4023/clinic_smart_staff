// controllers/eventController.js
const AttendanceEvent = require("../models/AttendanceEvent");
const TrustScore = require("../models/TrustScore");

const BASE_SCORE = 80;

// ✅ IMPORTANT: schema บังคับ cancelled_early (ไม่ใช่ cancelled)
const SCORE_RULES = {
  completed: +1,
  late: -2,
  cancelled_early: -5, // ✅ match schema
  no_show: -25,
};

// ✅ IMPORTANT: allow cancelled_early
const ALLOWED_STATUSES = ["completed", "late", "no_show", "cancelled_early"];

function clamp(n, a, b) {
  return Math.max(a, Math.min(b, n));
}

function normStatus(s) {
  return String(s || "").trim().toLowerCase();
}

// ✅ backward-compatible aliases -> normalize to schema value
function normalizeIncomingStatus(s) {
  const v = normStatus(s);

  // accept old/alias values
  if (v === "cancelled" || v === "cancel" || v === "canceled") {
    return "cancelled_early"; // ✅ map old cancel -> cancelled_early
  }
  if (v === "canceled_early" || v === "cancel_early") return "cancelled_early";

  return v;
}

// ======================================================
// ✅ NEW: score -> level
// ======================================================
function scoreToLevel(score) {
  const s = Number(score || 0);

  // ปรับ threshold ได้ทีหลังง่ายมาก
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

function ensureScoreDefaults(scoreDoc) {
  scoreDoc.totalShifts = Number(scoreDoc.totalShifts || 0);
  scoreDoc.completed = Number(scoreDoc.completed || 0);
  scoreDoc.late = Number(scoreDoc.late || 0);
  scoreDoc.noShow = Number(scoreDoc.noShow || 0);

  // ✅ model ของท่านใช้ cancelledEarly
  scoreDoc.cancelledEarly = Number(scoreDoc.cancelledEarly || 0);

  scoreDoc.flags = Array.isArray(scoreDoc.flags) ? scoreDoc.flags : [];
  scoreDoc.badges = Array.isArray(scoreDoc.badges) ? scoreDoc.badges : [];

  if (typeof scoreDoc.trustScore !== "number") scoreDoc.trustScore = BASE_SCORE;

  // ✅ defaults for new fields
  scoreDoc.level = (scoreDoc.level || "unknown").toString();
  scoreDoc.levelLabel = (scoreDoc.levelLabel || "ยังไม่มีข้อมูล").toString();
  scoreDoc.levelUpdatedAt = scoreDoc.levelUpdatedAt || null;

  // ✅ keep level in sync even for old docs
  updateLevel(scoreDoc);

  return scoreDoc;
}

function applyRules(scoreDoc, { status, minutesLate, occurredAt }) {
  ensureScoreDefaults(scoreDoc);

  const delta = SCORE_RULES[status] ?? 0;

  // ✅ late extra penalty (optional MVP rule)
  let finalDelta = delta;
  if (status === "late" && Number(minutesLate || 0) > 30) finalDelta -= 1;

  scoreDoc.totalShifts += 1;

  if (status === "completed") scoreDoc.completed += 1;
  if (status === "late") scoreDoc.late += 1;

  // ✅ cancelled_early -> count into cancelledEarly (ตาม model ใหม่)
  if (status === "cancelled_early") scoreDoc.cancelledEarly += 1;

  if (status === "no_show") {
    scoreDoc.noShow += 1;
    scoreDoc.lastNoShowAt = occurredAt;

    // ✅ set flag
    const flags = new Set(scoreDoc.flags);
    flags.add("NO_SHOW_30D");
    scoreDoc.flags = Array.from(flags);
  }

  scoreDoc.trustScore = clamp(scoreDoc.trustScore + finalDelta, 0, 100);

  // ✅ badges (simple MVP)
  const badges = new Set(scoreDoc.badges);
  const highlyReliable = scoreDoc.noShow === 0 && scoreDoc.totalShifts >= 10;

  if (highlyReliable) badges.add("HIGHLY_RELIABLE");
  else badges.delete("HIGHLY_RELIABLE");

  scoreDoc.badges = Array.from(badges);

  // ✅ NEW: update derived level after score change
  updateLevel(scoreDoc);

  return { scoreDoc, delta: finalDelta };
}

// ✅ POST /events/attendance
async function postAttendanceEvent(req, res) {
  try {
    // ✅ Allow either:
    // - Internal service call (X-Internal-Key -> middleware sets req.internal=true)
    // - Admin user JWT
    const { role } = req.user || {};
    const isInternal = req.internal === true || role === "system";

    if (!(isInternal || role === "admin")) {
      return res.status(403).json({ message: "Forbidden" });
    }

    const {
      clinicId,
      staffId,
      shiftId = "",
      status,
      minutesLate = 0,
      occurredAt,
    } = req.body || {};

    if (!clinicId || !staffId || !status || !occurredAt) {
      return res.status(400).json({
        message: "clinicId, staffId, status, occurredAt required",
        got: { clinicId, staffId, status, occurredAt },
        allowed: ALLOWED_STATUSES,
      });
    }

    // ✅ normalize incoming status (supports old clients)
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

    const minsLate = Number(minutesLate || 0);

    // ✅ save event (status MUST match schema enum)
    const event = await AttendanceEvent.create({
      clinicId,
      staffId,
      shiftId,
      status: st,
      minutesLate: minsLate,
      occurredAt: occ,
    });

    // ✅ upsert trustscore
    let scoreDoc = await TrustScore.findOne({ staffId });
    if (!scoreDoc) {
      scoreDoc = await TrustScore.create({
        staffId,
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

    const { delta } = applyRules(scoreDoc, {
      status: st,
      minutesLate: minsLate,
      occurredAt: occ,
    });

    await scoreDoc.save();

    return res.json({
      ok: true,
      applied: { status: st, delta },
      event,
      score: scoreDoc, // ✅ now includes level/label
    });
  } catch (e) {
    return res.status(500).json({
      message: "postAttendanceEvent failed",
      error: e.message || String(e),
    });
  }
}

module.exports = { postAttendanceEvent };