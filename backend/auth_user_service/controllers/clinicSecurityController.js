const bcrypt = require("bcryptjs");
const ClinicSecuritySetting = require("../models/ClinicSecuritySetting");

const IS_PROD = process.env.NODE_ENV === "production";

function s(v) {
  return String(v || "").trim();
}

function safeErrorMessage(fallback) {
  return IS_PROD ? fallback : undefined;
}

function getClinicId(req) {
  return s(req.user?.clinicId);
}

function getUserId(req) {
  return s(req.user?.userId);
}

function pickPin(body = {}) {
  return s(body.pin || body.newPin || body.clinicPin);
}

function isValidPin(pin) {
  return /^[0-9]{4,6}$/.test(s(pin));
}

function requireClinic(req, res) {
  const clinicId = getClinicId(req);

  if (!clinicId) {
    res.status(400).json({
      ok: false,
      code: "CLINIC_ID_REQUIRED",
      message: "clinicId is required",
    });
    return "";
  }

  return clinicId;
}

async function getPinStatus(req, res) {
  try {
    const clinicId = requireClinic(req, res);
    if (!clinicId) return;

    const setting = await ClinicSecuritySetting.findOne({ clinicId })
      .select("+pinHash clinicId pinUpdatedAt updatedAt")
      .lean();

    return res.json({
      ok: true,
      data: {
        clinicId,
        hasPin: !!s(setting?.pinHash),
        pinUpdatedAt: setting?.pinUpdatedAt || setting?.updatedAt || null,
      },
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      code: "PIN_STATUS_FAILED",
      message: safeErrorMessage("Failed to get PIN status") || e?.message || "Failed to get PIN status",
    });
  }
}

async function setClinicPin(req, res) {
  try {
    const clinicId = requireClinic(req, res);
    if (!clinicId) return;

    const pin = pickPin(req.body);

    if (!isValidPin(pin)) {
      return res.status(400).json({
        ok: false,
        code: "INVALID_PIN",
        message: "PIN must be 4-6 digits",
      });
    }

    const pinHash = await bcrypt.hash(pin, 10);
    const now = new Date();

    await ClinicSecuritySetting.findOneAndUpdate(
      { clinicId },
      {
        $set: {
          clinicId,
          pinHash,
          pinUpdatedAt: now,
          updatedBy: getUserId(req),
        },
      },
      {
        upsert: true,
        new: true,
        setDefaultsOnInsert: true,
      }
    );

    return res.json({
      ok: true,
      data: {
        clinicId,
        hasPin: true,
        pinUpdatedAt: now,
      },
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      code: "PIN_SET_FAILED",
      message: safeErrorMessage("Failed to set PIN") || e?.message || "Failed to set PIN",
    });
  }
}

async function verifyClinicPin(req, res) {
  try {
    const clinicId = requireClinic(req, res);
    if (!clinicId) return;

    const pin = pickPin(req.body);

    if (!isValidPin(pin)) {
      return res.status(400).json({
        ok: false,
        code: "INVALID_PIN",
        valid: false,
        message: "PIN must be 4-6 digits",
      });
    }

    const setting = await ClinicSecuritySetting.findOne({ clinicId })
      .select("+pinHash clinicId pinUpdatedAt")
      .lean();

    if (!setting || !s(setting.pinHash)) {
      return res.status(404).json({
        ok: false,
        code: "PIN_NOT_SET",
        valid: false,
        message: "Clinic PIN is not set",
      });
    }

    const valid = await bcrypt.compare(pin, setting.pinHash);

    return res.json({
      ok: true,
      data: {
        valid,
      },
      valid,
    });
  } catch (e) {
    return res.status(500).json({
      ok: false,
      code: "PIN_VERIFY_FAILED",
      valid: false,
      message: safeErrorMessage("Failed to verify PIN") || e?.message || "Failed to verify PIN",
    });
  }
}

module.exports = {
  getPinStatus,
  setClinicPin,
  verifyClinicPin,
};
