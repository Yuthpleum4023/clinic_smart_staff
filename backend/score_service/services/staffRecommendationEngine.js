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

function hasRiskFlag(flags) {
  const arr = ensureArray(flags);
  return arr.some((f) =>
    [
      "NO_SHOW_30D",
      "FRAUD_RISK_NO_SHOW_SPIKE",
      "FRAUD_RISK_LATE_PATTERN",
      "FRAUD_RISK_TOO_MANY_COMPLETED_1D",
      "FRAUD_RISK_DUPLICATE_EVENT_BURST",
    ].includes(f)
  );
}

function computeRecommendationScore({ clinicDoc, globalDoc }) {
  const clinicTrust = toNum(clinicDoc?.trustScore, 80);
  const globalTrust = toNum(globalDoc?.globalTrustScore, 80);

  const clinicShifts = toNum(clinicDoc?.totalShifts, 0);
  const globalShifts = toNum(globalDoc?.totalShifts, 0);

  let score = clinicTrust * 0.65 + globalTrust * 0.35;

  if (clinicShifts >= 20) score += 3;
  else if (clinicShifts >= 10) score += 2;
  else if (clinicShifts >= 5) score += 1;

  if (globalShifts >= 50) score += 2;
  else if (globalShifts >= 20) score += 1;

  if (ensureArray(clinicDoc?.badges).includes("HIGHLY_RELIABLE")) score += 3;
  if (ensureArray(globalDoc?.badges).includes("HIGHLY_RELIABLE")) score += 2;

  if (hasRiskFlag(clinicDoc?.flags)) score -= 15;
  if (hasRiskFlag(globalDoc?.flags)) score -= 10;

  return Math.max(0, Math.round(score * 100) / 100);
}

function buildReason(clinicDoc, globalDoc, finalScore) {
  const reasons = [];

  reasons.push(`recommendationScore ${finalScore}`);
  reasons.push(`clinicTrust ${toNum(clinicDoc?.trustScore, 80)}`);
  reasons.push(`globalTrust ${toNum(globalDoc?.globalTrustScore, 80)}`);

  if (toNum(clinicDoc?.totalShifts, 0) > 0) {
    reasons.push(`clinicShifts ${toNum(clinicDoc?.totalShifts, 0)}`);
  }

  if (ensureArray(clinicDoc?.badges).length) {
    reasons.push(...ensureArray(clinicDoc.badges).slice(0, 2));
  }

  if (ensureArray(globalDoc?.badges).length) {
    reasons.push(...ensureArray(globalDoc.badges).slice(0, 2));
  }

  return reasons;
}

/**
 * แนะนำ staff ให้คลินิกนั้น โดย:
 * - เน้น clinic score ของคลินิกนี้ก่อน
 * - ผสม global score
 * - ตัดคน risk หนักออกได้
 */
async function recommendStaffForClinic({
  clinicId,
  limit = 10,
  excludeRisk = true,
}) {
  const cid = normStr(clinicId);
  const safeLimit = Math.max(1, Math.min(toNum(limit, 10), 50));

  if (!cid) {
    throw new Error("clinicId is required");
  }

  const clinicDocs = await TrustScore.find({ clinicId: cid })
    .sort({ trustScore: -1, updatedAt: -1 })
    .limit(safeLimit * 5)
    .lean();

  const staffIds = clinicDocs.map((d) => normStr(d.staffId)).filter(Boolean);

  const globalDocs = staffIds.length
    ? await StaffGlobalScore.find({ staffId: { $in: staffIds } }).lean()
    : [];

  const globalMap = new Map(globalDocs.map((g) => [g.staffId, g]));

  const items = [];

  for (const c of clinicDocs) {
    const staffId = normStr(c.staffId);
    const globalDoc = globalMap.get(staffId) || null;

    if (excludeRisk) {
      if (hasRiskFlag(c.flags) || hasRiskFlag(globalDoc?.flags)) {
        continue;
      }
    }

    const recommendationScore = computeRecommendationScore({
      clinicDoc: c,
      globalDoc,
    });

    items.push({
      staffId,
      clinicId: cid,
      recommendationScore,
      clinicTrustScore: toNum(c.trustScore, 80),
      globalTrustScore: toNum(globalDoc?.globalTrustScore, 80),
      clinicLevel: normStr(c.level || "unknown"),
      globalLevel: normStr(globalDoc?.level || "unknown"),
      flags: [
        ...new Set([
          ...ensureArray(c.flags),
          ...ensureArray(globalDoc?.flags),
        ]),
      ],
      badges: [
        ...new Set([
          ...ensureArray(c.badges),
          ...ensureArray(globalDoc?.badges),
        ]),
      ],
      stats: {
        clinic: {
          totalShifts: toNum(c.totalShifts, 0),
          completed: toNum(c.completed, 0),
          late: toNum(c.late, 0),
          noShow: toNum(c.noShow, 0),
          cancelledEarly: toNum(c.cancelledEarly, 0),
        },
        global: {
          totalShifts: toNum(globalDoc?.totalShifts, 0),
          completed: toNum(globalDoc?.completed, 0),
          late: toNum(globalDoc?.late, 0),
          noShow: toNum(globalDoc?.noShow, 0),
          cancelledEarly: toNum(globalDoc?.cancelledEarly, 0),
        },
      },
      reason: buildReason(c, globalDoc, recommendationScore),
    });
  }

  items.sort((a, b) => {
    if (b.recommendationScore !== a.recommendationScore) {
      return b.recommendationScore - a.recommendationScore;
    }
    return b.clinicTrustScore - a.clinicTrustScore;
  });

  return items.slice(0, safeLimit);
}

module.exports = {
  recommendStaffForClinic,
  computeRecommendationScore,
};