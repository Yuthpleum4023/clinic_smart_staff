const TrustScore = require("../models/TrustScore");
const StaffGlobalScore = require("../models/StaffGlobalScore");

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

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

function deriveLevel(score) {
  const s = clamp(toNum(score, 80), 0, 100);

  if (s >= 90) return { level: "excellent", levelLabel: "ยอดเยี่ยม" };
  if (s >= 80) return { level: "good", levelLabel: "ดี" };
  if (s >= 60) return { level: "normal", levelLabel: "ปกติ" };
  return { level: "risk", levelLabel: "เสี่ยง" };
}

/**
 * กติกา decay/recovery
 * - no_show ล่าสุดผ่านไป >= 30 วัน -> +5
 * - late = 0 และ noShow = 0 และ cancelledEarly = 0 -> +2
 * - max recover per run = 10
 * - recover ได้ไม่เกิน 100
 */
function computeRecoveryDelta(doc, now = new Date()) {
  let delta = 0;

  const lastNoShowAt = doc.lastNoShowAt ? new Date(doc.lastNoShowAt) : null;
  const late = toNum(doc.late, 0);
  const noShow = toNum(doc.noShow, 0);
  const cancelledEarly = toNum(doc.cancelledEarly, 0);

  if (lastNoShowAt && !Number.isNaN(lastNoShowAt.getTime())) {
    const diffMs = now.getTime() - lastNoShowAt.getTime();
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffDays >= 30) {
      delta += 5;
    }
  }

  if (late === 0 && noShow === 0 && cancelledEarly === 0) {
    delta += 2;
  }

  return clamp(delta, 0, 10);
}

function applyDerivedFields(doc) {
  const derived = deriveLevel(doc.trustScore);
  doc.level = derived.level;
  doc.levelLabel = derived.levelLabel;
  doc.levelUpdatedAt = new Date();

  doc.flags = ensureArray(doc.flags);
  doc.badges = ensureArray(doc.badges);

  return doc;
}

function cleanupRecoverableFlags(doc, now = new Date()) {
  const flags = new Set(ensureArray(doc.flags));
  const lastNoShowAt = doc.lastNoShowAt ? new Date(doc.lastNoShowAt) : null;

  if (lastNoShowAt && !Number.isNaN(lastNoShowAt.getTime())) {
    const diffMs = now.getTime() - lastNoShowAt.getTime();
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffDays >= 30) {
      flags.delete("NO_SHOW_30D");
    }
  }

  doc.flags = Array.from(flags);
  return doc;
}

async function applyDecayToClinicScore(doc, now = new Date()) {
  if (!doc) return null;

  const before = toNum(doc.trustScore, 80);
  const delta = computeRecoveryDelta(doc, now);

  if (delta <= 0) {
    applyDerivedFields(doc);
    cleanupRecoverableFlags(doc, now);
    await doc.save();
    return {
      changed: false,
      beforeScore: before,
      afterScore: before,
      delta: 0,
      doc,
    };
  }

  doc.trustScore = clamp(before + delta, 0, 100);
  cleanupRecoverableFlags(doc, now);
  applyDerivedFields(doc);

  await doc.save();

  return {
    changed: doc.trustScore !== before,
    beforeScore: before,
    afterScore: doc.trustScore,
    delta,
    doc,
  };
}

async function runClinicScoreDecay({ clinicId, staffId } = {}) {
  const query = {};

  if (normStr(clinicId)) query.clinicId = normStr(clinicId);
  if (normStr(staffId)) query.staffId = normStr(staffId);

  const docs = await TrustScore.find(query);

  const results = [];

  for (const doc of docs) {
    const result = await applyDecayToClinicScore(doc);
    results.push({
      staffId: doc.staffId,
      clinicId: doc.clinicId,
      beforeScore: result.beforeScore,
      afterScore: result.afterScore,
      delta: result.delta,
      changed: result.changed,
    });
  }

  return results;
}

async function syncGlobalFromClinicScores(staffId) {
  const docs = await TrustScore.find({ staffId }).lean();

  if (!docs.length) return null;

  let weightedSum = 0;
  let totalWeight = 0;

  let totalShifts = 0;
  let completed = 0;
  let late = 0;
  let noShow = 0;
  let cancelledEarly = 0;

  const flags = new Set();
  const badges = new Set();

  for (const d of docs) {
    const score = toNum(d.trustScore, 80);
    const shifts = Math.max(toNum(d.totalShifts, 0), 1);

    weightedSum += score * shifts;
    totalWeight += shifts;

    totalShifts += toNum(d.totalShifts, 0);
    completed += toNum(d.completed, 0);
    late += toNum(d.late, 0);
    noShow += toNum(d.noShow, 0);
    cancelledEarly += toNum(d.cancelledEarly, 0);

    for (const f of ensureArray(d.flags)) flags.add(f);
    for (const b of ensureArray(d.badges)) badges.add(b);
  }

  const globalTrustScore = clamp(
    Math.round(weightedSum / Math.max(totalWeight, 1)),
    0,
    100
  );

  const derived = deriveLevel(globalTrustScore);

  const updated = await StaffGlobalScore.findOneAndUpdate(
    { staffId },
    {
      staffId,
      globalTrustScore,
      clinicCount: docs.length,
      totalShifts,
      completed,
      late,
      noShow,
      cancelledEarly,
      flags: Array.from(flags),
      badges: Array.from(badges),
      level: derived.level,
      levelLabel: derived.levelLabel,
      levelUpdatedAt: new Date(),
    },
    { new: true, upsert: true }
  );

  return updated;
}

async function runFullDecayAndSync({ clinicId, staffId } = {}) {
  const clinicResults = await runClinicScoreDecay({ clinicId, staffId });

  const affectedStaffIds = [...new Set(clinicResults.map((x) => x.staffId).filter(Boolean))];

  const globalResults = [];
  for (const sid of affectedStaffIds) {
    const globalDoc = await syncGlobalFromClinicScores(sid);
    if (globalDoc) {
      globalResults.push({
        staffId: globalDoc.staffId,
        globalTrustScore: globalDoc.globalTrustScore,
        clinicCount: globalDoc.clinicCount,
        level: globalDoc.level,
      });
    }
  }

  return {
    clinicResults,
    globalResults,
  };
}

module.exports = {
  computeRecoveryDelta,
  applyDecayToClinicScore,
  runClinicScoreDecay,
  syncGlobalFromClinicScores,
  runFullDecayAndSync,
};