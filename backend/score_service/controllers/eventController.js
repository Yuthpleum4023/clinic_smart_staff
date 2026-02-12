const AttendanceEvent = require("../models/AttendanceEvent");
const TrustScore = require("../models/TrustScore");

const BASE_SCORE = 80;

const SCORE_RULES = {
  completed: +1,
  late: -2,
  cancelled: -5,
  no_show: -25,
};

const ALLOWED_STATUSES = ["completed", "late", "no_show", "cancelled"];

function clamp(n, a, b) {
  return Math.max(a, Math.min(b, n));
}

function normStatus(s) {
  return String(s || "").trim().toLowerCase();
}

function ensureScoreDefaults(scoreDoc) {
  scoreDoc.totalShifts = Number(scoreDoc.totalShifts || 0);
  scoreDoc.completed = Number(scoreDoc.completed || 0);
  scoreDoc.late = Number(scoreDoc.late || 0);
  scoreDoc.noShow = Number(scoreDoc.noShow || 0);
  scoreDoc.cancelled = Number(scoreDoc.cancelled || 0);

  scoreDoc.flags = Array.isArray(scoreDoc.flags) ? scoreDoc.flags : [];
  scoreDoc.badges = Array.isArray(scoreDoc.badges) ? scoreDoc.badges : [];

  if (typeof scoreDoc.trustScore !== "number") scoreDoc.trustScore = BASE_SCORE;

  return scoreDoc;
}

function applyRules(scoreDoc, { status, minutesLate, occurredAt }) {
  ensureScoreDefaults(scoreDoc);

  let delta = SCORE_RULES[status] ?? 0;

  // ✅ late extra penalty (optional MVP rule)
  if (status === "late" && Number(minutesLate || 0) > 30) delta -= 1;

  scoreDoc.totalShifts += 1;

  if (status === "completed") scoreDoc.completed += 1;
  if (status === "late") scoreDoc.late += 1;
  if (status === "cancelled") scoreDoc.cancelled += 1;

  if (status === "no_show") {
    scoreDoc.noShow += 1;
    scoreDoc.lastNoShowAt = occurredAt;

    // ✅ set flag
    const flags = new Set(scoreDoc.flags);
    flags.add("NO_SHOW_30D");
    scoreDoc.flags = Array.from(flags);
  }

  scoreDoc.trustScore = clamp(scoreDoc.trustScore + delta, 0, 100);

  // ✅ badges (simple MVP)
  // - add HIGHLY_RELIABLE if noShow==0 and totalShifts>=10
  // - remove if condition no longer holds (avoid sticky badge)
  const badges = new Set(scoreDoc.badges);
  const highlyReliable = scoreDoc.noShow === 0 && scoreDoc.totalShifts >= 10;

  if (highlyReliable) badges.add("HIGHLY_RELIABLE");
  else badges.delete("HIGHLY_RELIABLE");

  scoreDoc.badges = Array.from(badges);

  return { scoreDoc, delta };
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
      return res
        .status(400)
        .json({ message: "clinicId, staffId, status, occurredAt required" });
    }

    const st = normStatus(status);
    if (!ALLOWED_STATUSES.includes(st)) {
      return res.status(400).json({ message: "Invalid status", allowed: ALLOWED_STATUSES });
    }

    const occ = new Date(occurredAt);
    if (Number.isNaN(occ.getTime())) {
      return res.status(400).json({ message: "occurredAt is invalid date" });
    }

    const minsLate = Number(minutesLate || 0);

    // ✅ save event
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
        cancelled: 0,
        lastNoShowAt: null,
        flags: [],
        badges: [],
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
      score: scoreDoc,
    });
  } catch (e) {
    return res.status(500).json({
      message: "postAttendanceEvent failed",
      error: e.message || String(e),
    });
  }
}

module.exports = { postAttendanceEvent };
