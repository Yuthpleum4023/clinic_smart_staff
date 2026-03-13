const TrustScore = require("../models/TrustScore");
const StaffGlobalScore = require("../models/StaffGlobalScore");

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

function deriveLevel(score) {
  if (score >= 90) return { level: "excellent", label: "ยอดเยี่ยม" };
  if (score >= 80) return { level: "good", label: "ดี" };
  if (score >= 60) return { level: "normal", label: "ปกติ" };
  return { level: "risk", label: "เสี่ยง" };
}

async function rebuildGlobalScoreForStaff(staffId) {
  const clinicScores = await TrustScore.find({ staffId }).lean();

  if (!clinicScores.length) return null;

  let totalShifts = 0;
  let completed = 0;
  let late = 0;
  let noShow = 0;
  let cancelledEarly = 0;

  let weightedScoreSum = 0;
  let totalWeight = 0;

  for (const c of clinicScores) {
    const shifts = Number(c.totalShifts || 0);

    totalShifts += shifts;
    completed += Number(c.completed || 0);
    late += Number(c.late || 0);
    noShow += Number(c.noShow || 0);
    cancelledEarly += Number(c.cancelledEarly || 0);

    const score = Number(c.trustScore || 80);

    weightedScoreSum += score * Math.max(shifts, 1);
    totalWeight += Math.max(shifts, 1);
  }

  const globalScore = clamp(
    Math.round(weightedScoreSum / Math.max(totalWeight, 1)),
    0,
    100
  );

  const { level, label } = deriveLevel(globalScore);

  const doc = await StaffGlobalScore.findOneAndUpdate(
    { staffId },
    {
      staffId,
      globalTrustScore: globalScore,
      clinicCount: clinicScores.length,
      totalShifts,
      completed,
      late,
      noShow,
      cancelledEarly,
      level,
      levelLabel: label,
      levelUpdatedAt: new Date(),
    },
    { upsert: true, new: true }
  );

  return doc;
}

module.exports = {
  rebuildGlobalScoreForStaff,
};