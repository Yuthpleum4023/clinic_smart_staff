// ==================================================
// controllers/clinicController.js
// PURPOSE:
// - Get current clinic from token
// - Used for employee check-in / redirect / UI
// ==================================================

const Clinic = require("../models/Clinic");

function s(v) {
  return String(v || "").trim();
}

// --------------------------------------------------
// GET MY CLINIC
// --------------------------------------------------
async function getMyClinic(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);

    if (!clinicId) {
      return res.status(401).json({
        ok: false,
        message: "Missing clinicId in token",
      });
    }

    const clinic = await Clinic.findOne({ clinicId }).lean();

    if (!clinic) {
      return res.status(404).json({
        ok: false,
        message: "Clinic not found",
      });
    }

    return res.json({
      ok: true,
      clinic,
    });
  } catch (err) {
    console.error("❌ getMyClinic error:", err);

    return res.status(500).json({
      ok: false,
      message: "getMyClinic failed",
      error: err.message,
    });
  }
}

module.exports = {
  getMyClinic,
};