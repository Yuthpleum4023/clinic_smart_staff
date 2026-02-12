// backend/auth_user_service/controllers/taxProfileController.js
const User = require("../models/User");

function toNumber(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function clampMin0(n) {
  return Math.max(0, toNumber(n));
}

function getUserId(req) {
  // รองรับ middleware ที่ set req.user หรือ req.userId
  return req.user?.id || req.user?._id || req.userId;
}

function currentTaxYear() {
  return new Date().getFullYear();
}

function sanitizePayload(body = {}) {
  const maritalStatus = String(body.maritalStatus || "single");
  const allowed = new Set(["single", "married_no_income", "married_with_income"]);

  return {
    maritalStatus: allowed.has(maritalStatus) ? maritalStatus : "single",
    childrenCount: clampMin0(body.childrenCount),

    supportFather: !!body.supportFather,
    supportMother: !!body.supportMother,
    supportSpouseFather: !!body.supportSpouseFather,
    supportSpouseMother: !!body.supportSpouseMother,

    lifeInsurance: clampMin0(body.lifeInsurance),
    healthInsuranceSelf: clampMin0(body.healthInsuranceSelf),
    healthInsuranceParents: clampMin0(body.healthInsuranceParents),
    ssf: clampMin0(body.ssf),
    rmf: clampMin0(body.rmf),
    pvd: clampMin0(body.pvd),

    homeLoanInterest: clampMin0(body.homeLoanInterest),

    donation: clampMin0(body.donation),
    donationEducation: clampMin0(body.donationEducation),

    updatedAt: new Date(),
  };
}

/**
 * GET /users/me/tax-profile?year=2026
 * - ถ้ายังไม่เคยกรอก => profile = null
 */
exports.getMyTaxProfile = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: "Unauthorized" });

    const year = Number(req.query.year) || currentTaxYear();

    const user = await User.findById(userId).select("taxProfiles").lean();
    if (!user) return res.status(404).json({ message: "User not found" });

    const found = (user.taxProfiles || []).find((p) => Number(p.taxYear) === year);

    return res.json({
      taxYear: year,
      profile: found || null,
    });
  } catch (err) {
    console.error("getMyTaxProfile error:", err);
    return res.status(500).json({ message: "Server error" });
  }
};

/**
 * PUT /users/me/tax-profile?year=2026
 * body: partial/full fields
 * - upsert: ไม่มีก็สร้าง, มีก็อัปเดต
 */
exports.upsertMyTaxProfile = async (req, res) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: "Unauthorized" });

    const year = Number(req.query.year) || currentTaxYear();
    const payload = sanitizePayload(req.body);

    const user = await User.findById(userId).select("taxProfiles");
    if (!user) return res.status(404).json({ message: "User not found" });

    user.taxProfiles = Array.isArray(user.taxProfiles) ? user.taxProfiles : [];

    const idx = user.taxProfiles.findIndex((p) => Number(p.taxYear) === year);

    if (idx === -1) {
      user.taxProfiles.push({ taxYear: year, ...payload });
    } else {
      // merge update (คง field อื่นไว้ แล้วทับด้วย payload)
      const prev = user.taxProfiles[idx].toObject ? user.taxProfiles[idx].toObject() : user.taxProfiles[idx];
      user.taxProfiles[idx] = { ...prev, ...payload, taxYear: year };
    }

    await user.save();

    const saved = user.taxProfiles.find((p) => Number(p.taxYear) === year);

    return res.json({
      taxYear: year,
      profile: saved || null,
    });
  } catch (err) {
    console.error("upsertMyTaxProfile error:", err);
    return res.status(500).json({ message: "Server error" });
  }
};
