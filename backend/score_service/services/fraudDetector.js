const AttendanceEvent = require("../models/AttendanceEvent");
const TrustScore = require("../models/TrustScore");
const StaffGlobalScore = require("../models/StaffGlobalScore");

function toNum(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function normStr(v) {
  return String(v || "").trim();
}

function ensureArray(v) {
  return Array.isArray(v)
    ? v.map((x) => String(x || "").trim()).filter(Boolean)
    : [];
}

function addFlags(existing, incoming) {
  const set = new Set(ensureArray(existing));
  for (const f of incoming) {
    const s = normStr(f);
    if (s) set.add(s);
  }
  return Array.from(set);
}

/**
 * MVP Fraud Rules
 * 1) no_show >= 3 ใน 30 วัน
 * 2) late >= 5 ใน 30 วัน
 * 3) completed เยอะผิดปกติใน 1 วัน (> 3)
 * 4) event ซ้ำเวลาใกล้กันมาก <= 60 วินาที
 */
async function detectFraudForClinicScore({ staffId, clinicId, now = new Date() }) {
  const sid = normStr(staffId);
  const cid = normStr(clinicId);

  if (!sid || !cid) {
    return {
      ok: false,
      message: "staffId and clinicId are required",
      flags: [],
    };
  }

  const day30 = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const day1 = new Date(now.getTime() - 1 * 24 * 60 * 60 * 1000);

  const events30d = await AttendanceEvent.find({
    staffId: sid,
    clinicId: cid,
    occurredAt: { $gte: day30 },
  })
    .sort({ occurredAt: 1 })
    .lean();

  const events1d = events30d.filter(
    (e) => new Date(e.occurredAt).getTime() >= day1.getTime()
  );

  const noShow30d = events30d.filter((e) => e.status === "no_show").length;
  const late30d = events30d.filter((e) => e.status === "late").length;
  const completed1d = events1d.filter((e) => e.status === "completed").length;

  let duplicateNearCount = 0;
  for (let i = 1; i < events30d.length; i++) {
    const prev = new Date(events30d[i - 1].occurredAt).getTime();
    const curr = new Date(events30d[i].occurredAt).getTime();
    const diffSec = Math.floor((curr - prev) / 1000);

    if (diffSec >= 0 && diffSec <= 60) {
      duplicateNearCount++;
    }
  }

  const flags = [];

  if (noShow30d >= 3) flags.push("FRAUD_RISK_NO_SHOW_SPIKE");
  if (late30d >= 5) flags.push("FRAUD_RISK_LATE_PATTERN");
  if (completed1d > 3) flags.push("FRAUD_RISK_TOO_MANY_COMPLETED_1D");
  if (duplicateNearCount >= 2) flags.push("FRAUD_RISK_DUPLICATE_EVENT_BURST");

  const scoreDoc = await TrustScore.findOne({ staffId: sid, clinicId: cid });
  if (!scoreDoc) {
    return {
      ok: true,
      message: "score doc not found",
      flags,
    };
  }

  scoreDoc.flags = addFlags(scoreDoc.flags, flags);
  await scoreDoc.save();

  return {
    ok: true,
    staffId: sid,
    clinicId: cid,
    flags,
    stats: {
      noShow30d,
      late30d,
      completed1d,
      duplicateNearCount,
    },
  };
}

async function syncFraudFlagsToGlobal(staffId) {
  const sid = normStr(staffId);
  if (!sid) return null;

  const clinicDocs = await TrustScore.find({ staffId: sid }).lean();
  if (!clinicDocs.length) return null;

  const mergedFlags = new Set();
  const mergedBadges = new Set();

  for (const d of clinicDocs) {
    for (const f of ensureArray(d.flags)) mergedFlags.add(f);
    for (const b of ensureArray(d.badges)) mergedBadges.add(b);
  }

  const updated = await StaffGlobalScore.findOneAndUpdate(
    { staffId: sid },
    {
      $set: {
        flags: Array.from(mergedFlags),
        badges: Array.from(mergedBadges),
      },
    },
    { new: true }
  );

  return updated;
}

async function detectAndSyncFraud({ staffId, clinicId }) {
  const clinicResult = await detectFraudForClinicScore({ staffId, clinicId });
  const globalDoc = await syncFraudFlagsToGlobal(staffId);

  return {
    clinicResult,
    globalResult: globalDoc
      ? {
          staffId: globalDoc.staffId,
          flags: globalDoc.flags || [],
          badges: globalDoc.badges || [],
        }
      : null,
  };
}

module.exports = {
  detectFraudForClinicScore,
  syncFraudFlagsToGlobal,
  detectAndSyncFraud,
};