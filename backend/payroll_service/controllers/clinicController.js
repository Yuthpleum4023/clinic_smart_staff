// payroll_service/controllers/clinicController.js
//
// ✅ FULL FILE (ADD: patchMyClinicProfile + socialSecurity config + clinic branding/profile fields)
// - ✅ PATCH /clinics/:clinicId/location (admin)
// - ✅ PATCH /clinics/me/location        (admin)
// - ✅ PATCH /clinics/me/profile         (admin)
// - ✅ GET /clinics/:clinicId            (auth)
//
// ✅ NEW:
// - รองรับอัปเดต socialSecurity config ของคลินิกผ่าน:
//   - PATCH /clinics/me/profile
//   - PATCH /clinics/:clinicId/location
//
// Supported fields:
// - socialSecurityEnabled
// - socialSecurityEmployeeRate
// - socialSecurityMaxWageBase
//
// หรือส่ง nested ได้:
// {
//   socialSecurity: {
//     enabled: true,
//     employeeRate: 0.05,
//     maxWageBase: 17500
//   }
// }
//
// ✅ NEW PROFILE FIELDS:
// - branchName
// - taxId
// - logoUrl
//

const Clinic = require("../models/Clinic");
const ShiftNeed = require("../models/ShiftNeed");
const Shift = require("../models/Shift");

// ---------------- helpers ----------------
function s(v) {
  return (v ?? "").toString().trim();
}

function numOrNull(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  if (Number.isNaN(n) || !Number.isFinite(n)) return null;
  return n;
}

function isValidLatLng(lat, lng) {
  if (lat === null || lng === null) return false;
  if (typeof lat !== "number" || typeof lng !== "number") return false;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (lat < -90 || lat > 90) return false;
  if (lng < -180 || lng > 180) return false;
  return true;
}

function mustAdmin(req, res) {
  const role = s(req.user?.role).toLowerCase();
  if (role !== "admin") {
    res.status(403).json({ message: "Forbidden (admin only)" });
    return false;
  }
  return true;
}

function parseBool(v, defaultVal = false) {
  if (v === undefined || v === null) return defaultVal;
  if (typeof v === "boolean") return v;
  const t = String(v).trim().toLowerCase();
  if (t === "true" || t === "1" || t === "yes" || t === "y") return true;
  if (t === "false" || t === "0" || t === "no" || t === "n") return false;
  return defaultVal;
}

function rid() {
  return Math.random().toString(36).slice(2, 8);
}

function previewToken(authHeader) {
  if (!authHeader) return "-";
  const t = String(authHeader).replace(/^Bearer\s+/i, "").trim();
  if (!t) return "-";
  return t.slice(0, 24);
}

function isValidThaiPhoneDigits(phone) {
  if (!phone) return false;
  return /^\d{9,10}$/.test(phone);
}

function hasOwn(obj, key) {
  return Object.prototype.hasOwnProperty.call(obj || {}, key);
}

function isLikelyHttpUrl(url) {
  const x = s(url);
  if (!x) return true;
  return /^https?:\/\/\S+$/i.test(x);
}

function normalizeClinicProfileFields(body = {}) {
  const patch = {};
  let touched = false;

  const clinicName = s(body.clinicName ?? body.name);
  const clinicPhone = s(body.clinicPhone ?? body.phone);
  const clinicAddress = s(body.clinicAddress ?? body.address);
  const branchName = s(body.branchName);
  const taxId = s(body.taxId);
  const logoUrl = s(body.logoUrl);

  if (hasOwn(body, "clinicName") || hasOwn(body, "name")) {
    patch.name = clinicName;
    touched = true;
  }

  if (hasOwn(body, "clinicPhone") || hasOwn(body, "phone")) {
    if (clinicPhone && !isValidThaiPhoneDigits(clinicPhone)) {
      return {
        ok: false,
        message: "Invalid clinicPhone",
        hint: "phone must be 9-10 digits",
        got: clinicPhone,
      };
    }
    patch.phone = clinicPhone;
    touched = true;
  }

  if (hasOwn(body, "clinicAddress") || hasOwn(body, "address")) {
    patch.address = clinicAddress;
    touched = true;
  }

  if (hasOwn(body, "branchName")) {
    patch.branchName = branchName;
    touched = true;
  }

  if (hasOwn(body, "taxId")) {
    patch.taxId = taxId;
    touched = true;
  }

  if (hasOwn(body, "logoUrl")) {
    if (logoUrl && !isLikelyHttpUrl(logoUrl)) {
      return {
        ok: false,
        message: "Invalid logoUrl",
        hint: "Use a full http/https URL",
        got: logoUrl,
      };
    }
    patch.logoUrl = logoUrl;
    touched = true;
  }

  return { ok: true, touched, $set: patch };
}

function resolveSocialSecurityPatch(body = {}) {
  const out = {};
  let touched = false;

  const nested =
    body.socialSecurity && typeof body.socialSecurity === "object"
      ? body.socialSecurity
      : {};

  const hasEnabled =
    hasOwn(body, "socialSecurityEnabled") || hasOwn(nested, "enabled");
  const hasEmployeeRate =
    hasOwn(body, "socialSecurityEmployeeRate") ||
    hasOwn(nested, "employeeRate");
  const hasMaxWageBase =
    hasOwn(body, "socialSecurityMaxWageBase") ||
    hasOwn(nested, "maxWageBase");

  if (hasEnabled) {
    const enabled = hasOwn(body, "socialSecurityEnabled")
      ? parseBool(body.socialSecurityEnabled, true)
      : parseBool(nested.enabled, true);

    out["socialSecurity.enabled"] = enabled;
    touched = true;
  }

  if (hasEmployeeRate) {
    const raw = hasOwn(body, "socialSecurityEmployeeRate")
      ? body.socialSecurityEmployeeRate
      : nested.employeeRate;

    const v = numOrNull(raw);
    if (v === null || v < 0 || v > 1) {
      return {
        ok: false,
        message: "Invalid socialSecurityEmployeeRate",
        hint: "Use decimal เช่น 0.05 for 5%",
        got: raw,
      };
    }

    out["socialSecurity.employeeRate"] = v;
    touched = true;
  }

  if (hasMaxWageBase) {
    const raw = hasOwn(body, "socialSecurityMaxWageBase")
      ? body.socialSecurityMaxWageBase
      : nested.maxWageBase;

    const v = numOrNull(raw);
    if (v === null || v < 0 || v > 1000000) {
      return {
        ok: false,
        message: "Invalid socialSecurityMaxWageBase",
        hint: "Use a positive number เช่น 17500",
        got: raw,
      };
    }

    out["socialSecurity.maxWageBase"] = v;
    touched = true;
  }

  return { ok: true, touched, $set: out };
}

// ---------------- controllers ----------------

// PATCH /clinics/:clinicId/location (admin)
// body:
// {
//   clinicLat?, clinicLng?, clinicName?, clinicPhone?, clinicAddress?,
//   branchName?, taxId?, logoUrl?, backfill?,
//   socialSecurityEnabled?, socialSecurityEmployeeRate?, socialSecurityMaxWageBase?,
//   socialSecurity?: { enabled?, employeeRate?, maxWageBase? }
// }
async function patchClinicLocation(req, res) {
  const _rid = rid();
  const t0 = Date.now();

  try {
    console.log("======================================");
    console.log(`📍 [${_rid}] PATCH /clinics/:clinicId/location HIT`);
    console.log("Host:", req.get("host"));
    console.log("Authorization:", req.get("authorization") ? "YES" : "NO");
    console.log("Token Preview:", previewToken(req.get("authorization")));
    console.log("User:", req.user);
    console.log("Params:", req.params);
    console.log("Body:", req.body);

    if (!mustAdmin(req, res)) {
      console.log(`⛔ [${_rid}] forbidden (not admin)`);
      console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
      console.log("======================================");
      return;
    }

    const clinicId = s(req.params.clinicId || "");
    if (!clinicId) {
      console.log(`❌ [${_rid}] missing clinicId`);
      return res.status(400).json({ message: "clinicId required" });
    }

    const lat = numOrNull(req.body?.clinicLat ?? req.body?.lat);
    const lng = numOrNull(req.body?.clinicLng ?? req.body?.lng);
    const hasLatLngInput = lat !== null || lng !== null;

    if (hasLatLngInput) {
      if (!isValidLatLng(lat, lng)) {
        console.log(`❌ [${_rid}] invalid lat/lng`);
        return res.status(400).json({
          message: "Invalid clinicLat/clinicLng",
          hint: "lat in [-90..90], lng in [-180..180]",
          got: { lat, lng },
        });
      }
    }

    const profilePatch = normalizeClinicProfileFields(req.body || {});
    if (!profilePatch.ok) {
      return res.status(400).json({
        message: profilePatch.message,
        hint: profilePatch.hint,
        got: profilePatch.got,
      });
    }

    const doBackfill = parseBool(req.body?.backfill, false);

    if (doBackfill && !hasLatLngInput) {
      console.log(`❌ [${_rid}] backfill without lat/lng`);
      return res.status(400).json({
        message: "backfill requires clinicLat/clinicLng",
      });
    }

    const ssoPatch = resolveSocialSecurityPatch(req.body || {});
    if (!ssoPatch.ok) {
      return res.status(400).json({
        message: ssoPatch.message,
        hint: ssoPatch.hint,
        got: ssoPatch.got,
      });
    }

    const $set = {
      clinicId,
      ...(hasLatLngInput ? { lat, lng } : {}),
      ...profilePatch.$set,
      ...ssoPatch.$set,
    };

    const updated = await Clinic.findOneAndUpdate(
      { clinicId },
      { $set },
      { new: true, upsert: true }
    ).lean();

    console.log(`✅ [${_rid}] clinic updated`);

    let backfill = { ok: false, shiftneedsUpdated: 0, shiftsUpdated: 0 };

    if (doBackfill) {
      const needRes = await ShiftNeed.updateMany(
        { clinicId },
        {
          $set: {
            clinicLat: lat,
            clinicLng: lng,
            clinicName: s(updated?.name),
            clinicPhone: s(updated?.phone),
            clinicAddress: s(updated?.address),
          },
        }
      );

      const shiftRes = await Shift.updateMany(
        { clinicId },
        {
          $set: {
            clinicLat: lat,
            clinicLng: lng,
            clinicName: s(updated?.name),
            clinicPhone: s(updated?.phone),
            clinicAddress: s(updated?.address),
          },
        }
      );

      backfill = {
        ok: true,
        shiftneedsUpdated: Number(needRes?.modifiedCount || 0),
        shiftsUpdated: Number(shiftRes?.modifiedCount || 0),
      };

      console.log(`🧩 [${_rid}] backfill done`, backfill);
    }

    console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
    console.log("======================================");

    return res.json({ ok: true, clinic: updated, backfill });
  } catch (e) {
    console.log(`💥 [${_rid}] ERROR`, e);
    return res.status(500).json({
      message: "patchClinicLocation failed",
      error: e?.message || String(e),
    });
  }
}

// PATCH /clinics/me/location (admin)
async function patchMyClinicLocation(req, res) {
  const clinicId = s(req.user?.clinicId);

  if (!clinicId) {
    return res.status(400).json({ message: "missing clinicId in token" });
  }

  req.params.clinicId = clinicId;
  return patchClinicLocation(req, res);
}

// PATCH /clinics/me/profile (admin)
// body:
// {
//   clinicName?, clinicPhone?, clinicAddress?,
//   branchName?, taxId?, logoUrl?,
//   socialSecurityEnabled?, socialSecurityEmployeeRate?, socialSecurityMaxWageBase?,
//   socialSecurity?: { enabled?, employeeRate?, maxWageBase? }
// }
async function patchMyClinicProfile(req, res) {
  const _rid = rid();
  const t0 = Date.now();

  try {
    console.log("======================================");
    console.log(`🧾 [${_rid}] PATCH /clinics/me/profile HIT`);
    console.log("Host:", req.get("host"));
    console.log("Authorization:", req.get("authorization") ? "YES" : "NO");
    console.log("Token Preview:", previewToken(req.get("authorization")));
    console.log("User:", req.user);
    console.log("Body:", req.body);

    if (!mustAdmin(req, res)) {
      console.log(`⛔ [${_rid}] forbidden (not admin)`);
      console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
      console.log("======================================");
      return;
    }

    const clinicId = s(req.user?.clinicId);
    if (!clinicId) {
      console.log(`❌ [${_rid}] missing clinicId in token`);
      return res.status(400).json({ message: "missing clinicId in token" });
    }

    const profilePatch = normalizeClinicProfileFields(req.body || {});
    if (!profilePatch.ok) {
      return res.status(400).json({
        message: profilePatch.message,
        hint: profilePatch.hint,
        got: profilePatch.got,
      });
    }

    const ssoPatch = resolveSocialSecurityPatch(req.body || {});
    if (!ssoPatch.ok) {
      return res.status(400).json({
        message: ssoPatch.message,
        hint: ssoPatch.hint,
        got: ssoPatch.got,
      });
    }

    if (!profilePatch.touched && !ssoPatch.touched) {
      return res.status(400).json({
        message: "No fields to update",
        hint:
          "Send at least one of clinicName / clinicPhone / clinicAddress / branchName / taxId / logoUrl / socialSecurity*",
      });
    }

    const $set = {
      ...profilePatch.$set,
      ...ssoPatch.$set,
    };

    const updated = await Clinic.findOneAndUpdate(
      { clinicId },
      { $set },
      { new: true, upsert: true }
    ).lean();

    console.log(`✅ [${_rid}] profile updated`, {
      clinicId,
      name: updated?.name,
      phone: updated?.phone,
      branchName: updated?.branchName,
      taxId: updated?.taxId,
      logoUrl: updated?.logoUrl,
      socialSecurity: updated?.socialSecurity,
    });

    console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
    console.log("======================================");

    return res.json({ ok: true, clinic: updated });
  } catch (e) {
    console.log(`💥 [${_rid}] ERROR`, e);
    return res.status(500).json({
      message: "patchMyClinicProfile failed",
      error: e?.message || String(e),
    });
  }
}

// GET /clinics/:clinicId (auth)
async function getClinic(req, res) {
  try {
    const clinicId = s(req.params.clinicId || "");
    if (!clinicId) {
      return res.status(400).json({ message: "clinicId required" });
    }

    const row = await Clinic.findOne({ clinicId }).lean();
    if (!row) {
      return res.status(404).json({ message: "clinic not found" });
    }

    return res.json({ ok: true, clinic: row });
  } catch (e) {
    return res.status(500).json({
      message: "getClinic failed",
      error: e?.message || String(e),
    });
  }
}

module.exports = {
  patchClinicLocation,
  patchMyClinicLocation,
  patchMyClinicProfile,
  getClinic,
};