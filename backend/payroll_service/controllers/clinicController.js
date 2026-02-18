// payroll_service/controllers/clinicController.js
//
// ✅ FULL FILE (LONG-TERM FIX)
// - ✅ PATCH /clinics/:clinicId/location (admin)  (ของเดิม)
// - ✅ PATCH /clinics/me/location        (admin)  (ใหม่: ใช้ clinicId จาก token กันยิงผิด)
// - ✅ (optional) backfill shiftneeds/shifts ที่ clinicLat/clinicLng ยัง null ตอน patch location (เปิด default=true)
//
// Notes:
// - ต้องมี auth middleware ใส่ req.user = { role, clinicId, ... }
// - models ที่ต้องมีใน payroll_service:
//   - models/Clinic.js
//   - models/ShiftNeed.js
//   - models/Shift.js

const Clinic = require("../models/Clinic");
const ShiftNeed = require("../models/ShiftNeed");
const Shift = require("../models/Shift");

// ---------------- helpers ----------------
function s(v) {
  return (v ?? "").toString().trim();
}

function numOrNull(v) {
  if (v === null || v === undefined) return null;
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
    return res.status(403).json({ message: "Forbidden (admin only)" });
  }
  return true;
}

function parseBool(v, defaultVal = true) {
  if (v === undefined || v === null) return defaultVal;
  if (typeof v === "boolean") return v;
  const t = String(v).trim().toLowerCase();
  if (t === "true" || t === "1" || t === "yes" || t === "y") return true;
  if (t === "false" || t === "0" || t === "no" || t === "n") return false;
  return defaultVal;
}

// ---------------- controllers ----------------

// PATCH /clinics/:clinicId/location   (admin)
// body: { clinicLat, clinicLng, clinicName, clinicPhone, clinicAddress, backfill? }
async function patchClinicLocation(req, res) {
  try {
    if (!mustAdmin(req, res)) return;

    const clinicId = s(req.params.clinicId || "");
    if (!clinicId) return res.status(400).json({ message: "clinicId required" });

    const lat = numOrNull(req.body?.clinicLat ?? req.body?.lat);
    const lng = numOrNull(req.body?.clinicLng ?? req.body?.lng);

    if (!isValidLatLng(lat, lng)) {
      return res.status(400).json({
        message: "Invalid clinicLat/clinicLng",
        hint: "lat in [-90..90], lng in [-180..180]",
      });
    }

    const name = s(req.body?.clinicName ?? req.body?.name);
    const phone = s(req.body?.clinicPhone ?? req.body?.phone);
    const address = s(req.body?.clinicAddress ?? req.body?.address);

    const updated = await Clinic.findOneAndUpdate(
      { clinicId },
      {
        $set: {
          clinicId,
          lat,
          lng,
          ...(name ? { name } : {}),
          ...(phone ? { phone } : {}),
          ...(address ? { address } : {}),
        },
      },
      { new: true, upsert: true }
    ).lean();

    // ✅ optional: backfill old data (ShiftNeed + Shift) that still has null lat/lng
    const doBackfill = parseBool(req.body?.backfill, true);

    let backfill = { ok: false, shiftneedsUpdated: 0, shiftsUpdated: 0 };
    if (doBackfill) {
      const needRes = await ShiftNeed.updateMany(
        {
          clinicId,
          $or: [
            { clinicLat: null },
            { clinicLng: null },
            { clinicLat: { $exists: false } },
            { clinicLng: { $exists: false } },
          ],
        },
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
        {
          clinicId,
          $or: [
            { clinicLat: null },
            { clinicLng: null },
            { clinicLat: { $exists: false } },
            { clinicLng: { $exists: false } },
          ],
        },
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
    }

    return res.json({ ok: true, clinic: updated, backfill });
  } catch (e) {
    return res.status(500).json({
      message: "patchClinicLocation failed",
      error: e.message || String(e),
    });
  }
}

// ✅ NEW: PATCH /clinics/me/location (admin)
// body: { clinicLat, clinicLng, clinicName, clinicPhone, clinicAddress, backfill? }
// - ใช้ clinicId จาก token -> กันคนยิงผิด clinicId แล้วไปอัปเดตคลินิกคนอื่น
async function patchMyClinicLocation(req, res) {
  try {
    if (!mustAdmin(req, res)) return;

    const clinicId = s(req.user?.clinicId);
    if (!clinicId) {
      return res.status(400).json({ message: "missing clinicId in token" });
    }

    // reuse handler เดิม
    req.params = req.params || {};
    req.params.clinicId = clinicId;

    return patchClinicLocation(req, res);
  } catch (e) {
    return res.status(500).json({
      message: "patchMyClinicLocation failed",
      error: e.message || String(e),
    });
  }
}

// GET /clinics/:clinicId  (auth)  (เอาไว้ดูค่าที่บันทึก)
async function getClinic(req, res) {
  try {
    const clinicId = s(req.params.clinicId || "");
    if (!clinicId) return res.status(400).json({ message: "clinicId required" });

    const row = await Clinic.findOne({ clinicId }).lean();
    if (!row) return res.status(404).json({ message: "clinic not found" });

    return res.json({ ok: true, clinic: row });
  } catch (e) {
    return res.status(500).json({
      message: "getClinic failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  patchClinicLocation,
  patchMyClinicLocation,
  getClinic,
};
