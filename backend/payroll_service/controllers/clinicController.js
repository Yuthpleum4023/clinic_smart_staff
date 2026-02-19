// payroll_service/controllers/clinicController.js
//
// ✅ FULL FILE (DEBUG LOG + FIX mustAdmin + FAST DEFAULT)
// - ✅ PATCH /clinics/:clinicId/location (admin)
// - ✅ PATCH /clinics/me/location        (admin)
// - ✅ FIX: mustAdmin return boolean จริง (กันไหลต่อหลังส่ง 403)
// - ✅ FIX: backfill default = false (กัน request ค้าง/timeout 30s)
// - ✅ ADD: logs + timing + mongo result counts
//

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

// ✅✅✅ FIX: ต้องคืน boolean เท่านั้น
function mustAdmin(req, res) {
  const role = s(req.user?.role).toLowerCase();
  if (role !== "admin") {
    res.status(403).json({ message: "Forbidden (admin only)" });
    return false;
  }
  return true;
}

// ✅ เปลี่ยน defaultVal เป็น false เพื่อกันค้าง/timeout
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

// ---------------- controllers ----------------

// PATCH /clinics/:clinicId/location   (admin)
// body: { clinicLat, clinicLng, clinicName, clinicPhone, clinicAddress, backfill? }
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
      console.log(`❌ [${_rid}] missing clinicId param`);
      console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
      console.log("======================================");
      return res.status(400).json({ message: "clinicId required" });
    }

    const lat = numOrNull(req.body?.clinicLat ?? req.body?.lat);
    const lng = numOrNull(req.body?.clinicLng ?? req.body?.lng);

    console.log(`🧭 [${_rid}] parsed lat/lng:`, { lat, lng });

    if (!isValidLatLng(lat, lng)) {
      console.log(`❌ [${_rid}] invalid lat/lng`);
      console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
      console.log("======================================");
      return res.status(400).json({
        message: "Invalid clinicLat/clinicLng",
        hint: "lat in [-90..90], lng in [-180..180]",
        got: { lat, lng },
      });
    }

    const name = s(req.body?.clinicName ?? req.body?.name);
    const phone = s(req.body?.clinicPhone ?? req.body?.phone);
    const address = s(req.body?.clinicAddress ?? req.body?.address);

    console.log(`🧾 [${_rid}] update clinic:`, { clinicId, name, phone, address });

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

    console.log(`✅ [${_rid}] clinic updated`, {
      clinicId,
      lat: updated?.lat,
      lng: updated?.lng,
    });

    // ✅ optional backfill (default=false กันค้าง)
    const doBackfill = parseBool(req.body?.backfill, false);
    console.log(`🧩 [${_rid}] backfill?`, doBackfill);

    let backfill = { ok: false, shiftneedsUpdated: 0, shiftsUpdated: 0 };

    if (doBackfill) {
      const bt0 = Date.now();

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

      console.log(`🧩 [${_rid}] backfill done in ${Date.now() - bt0}ms`, backfill);
    }

    console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
    console.log("======================================");

    return res.json({ ok: true, clinic: updated, backfill });
  } catch (e) {
    console.log(`💥 [${_rid}] ERROR`, e);
    console.log(`⏱️ [${_rid}] failed in ${Date.now() - t0}ms`);
    console.log("======================================");

    return res.status(500).json({
      message: "patchClinicLocation failed",
      error: e?.message || String(e),
    });
  }
}

// ✅ NEW: PATCH /clinics/me/location (admin)
// body: { clinicLat, clinicLng, clinicName, clinicPhone, clinicAddress, backfill? }
async function patchMyClinicLocation(req, res) {
  const _rid = rid();
  const t0 = Date.now();

  try {
    console.log("======================================");
    console.log(`📍 [${_rid}] PATCH /clinics/me/location HIT`);
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
      console.log(`⏱️ [${_rid}] done in ${Date.now() - t0}ms`);
      console.log("======================================");
      return res.status(400).json({ message: "missing clinicId in token" });
    }

    // reuse handler เดิม
    req.params = req.params || {};
    req.params.clinicId = clinicId;

    console.log(`➡️ [${_rid}] forward to patchClinicLocation with clinicId=${clinicId}`);
    console.log("======================================");

    return patchClinicLocation(req, res);
  } catch (e) {
    console.log(`💥 [${_rid}] ERROR`, e);
    console.log(`⏱️ [${_rid}] failed in ${Date.now() - t0}ms`);
    console.log("======================================");

    return res.status(500).json({
      message: "patchMyClinicLocation failed",
      error: e?.message || String(e),
    });
  }
}

// GET /clinics/:clinicId
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
