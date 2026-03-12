// payroll_service/controllers/shiftController.js
const mongoose = require("mongoose");
const Shift = require("../models/Shift");

// ✅ OPTIONAL: ถ้ามี models/Clinic.js จะดึงพิกัดคลินิกมาเติมให้
let Clinic = null;
try {
  Clinic = require("../models/Clinic");
} catch (_) {
  Clinic = null;
}

// -------------------- Helpers --------------------
function mustBeAdmin(req, res) {
  const role = req.user?.role;
  if (role !== "admin") {
    res.status(403).json({ message: "Forbidden (admin only)" });
    return false;
  }
  return true;
}

function s(v) {
  return (v ?? "").toString().trim();
}

function numOrNull(v) {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  if (Number.isNaN(n)) return null;
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

function pickClinicLatLngFromClinicDoc(doc) {
  if (!doc) {
    return {
      clinicLat: null,
      clinicLng: null,
      clinicPhone: "",
      clinicName: "",
      clinicAddress: "",
    };
  }

  const d = typeof doc.toObject === "function" ? doc.toObject() : doc;

  const name = s(d.name || d.clinicName || d.title);
  const phone = s(d.phone || d.contactPhone || d.clinicPhone);
  const addr = s(d.address || d.locationAddress || d.fullAddress);

  const lat =
    numOrNull(d.lat) ??
    numOrNull(d.clinicLat) ??
    numOrNull(d.location?.lat) ??
    numOrNull(d.location?.latitude);

  const lng =
    numOrNull(d.lng) ??
    numOrNull(d.clinicLng) ??
    numOrNull(d.location?.lng) ??
    numOrNull(d.location?.longitude);

  return {
    clinicLat: isValidLatLng(lat, lng) ? lat : null,
    clinicLng: isValidLatLng(lat, lng) ? lng : null,
    clinicPhone: phone,
    clinicName: name,
    clinicAddress: addr,
  };
}

function isObjectIdString(x) {
  const v = s(x);
  return !!v && mongoose.Types.ObjectId.isValid(v);
}

async function loadClinicMapByIds(ids = []) {
  if (!Clinic) return new Map();

  const clean = [...new Set(ids.map((x) => s(x)).filter(Boolean))];
  if (!clean.length) return new Map();

  const oidList = clean.filter(isObjectIdString);
  const strList = clean.filter((x) => !isObjectIdString(x));

  const or = [];
  if (oidList.length) or.push({ _id: { $in: oidList } });
  if (strList.length) {
    or.push({ clinicId: { $in: strList } });
    or.push({ id: { $in: strList } });
  }

  if (!or.length) return new Map();

  const rows = await Clinic.find({ $or: or }).lean();

  const m = new Map();
  for (const r of rows) {
    const picked = pickClinicLatLngFromClinicDoc(r);

    const key1 = s(r._id);
    const key2 = s(r.clinicId);
    const key3 = s(r.id);

    if (key1) m.set(key1, picked);
    if (key2) m.set(key2, picked);
    if (key3) m.set(key3, picked);
  }
  return m;
}

function normalizeShiftOutput(row, clinicMap = new Map()) {
  const out = {
    ...row,
    staffId: s(row.staffId),
    helperUserId: s(row.helperUserId),
    clinicId: s(row.clinicId),
    date: s(row.date),
    start: s(row.start),
    end: s(row.end),
    note: s(row.note),
    clinicLat: row.clinicLat ?? null,
    clinicLng: row.clinicLng ?? null,
    clinicName: s(row.clinicName),
    clinicPhone: s(row.clinicPhone),
    clinicAddress: s(row.clinicAddress),
  };

  const hasLatLng = isValidLatLng(
    numOrNull(out.clinicLat),
    numOrNull(out.clinicLng)
  );

  if (!hasLatLng) {
    const picked = clinicMap.get(s(out.clinicId));
    if (picked) {
      out.clinicLat = picked.clinicLat;
      out.clinicLng = picked.clinicLng;

      if (!s(out.clinicPhone)) out.clinicPhone = picked.clinicPhone;
      if (!s(out.clinicName)) out.clinicName = picked.clinicName;
      if (!s(out.clinicAddress)) out.clinicAddress = picked.clinicAddress;
    }
  }

  return out;
}

// -------------------- Controllers --------------------

// POST /shifts (admin)
async function createShift(req, res) {
  try {
    if (!mustBeAdmin(req, res)) return;

    const {
      clinicId,
      staffId,
      helperUserId,
      date,
      start,
      end,
      hourlyRate = 0,
      note = "",
      clinicLat,
      clinicLng,
      clinicPhone,
      clinicName,
      clinicAddress,
      status,
    } = req.body || {};

    const cid = s(clinicId);
    const sid = s(staffId);
    const hid = s(helperUserId);
    const d = s(date);
    const st = s(start);
    const en = s(end);

    // ✅ รองรับทั้ง employee และ helper
    if (!cid || (!sid && !hid) || !d || !st || !en) {
      return res.status(400).json({
        message:
          "clinicId + (staffId or helperUserId) + date + start + end required",
      });
    }

    const lat = numOrNull(clinicLat);
    const lng = numOrNull(clinicLng);

    const created = await Shift.create({
      clinicId: cid,
      staffId: sid,
      helperUserId: hid,
      date: d,
      start: st,
      end: en,
      status: s(status) || "scheduled",
      hourlyRate: Number(hourlyRate || 0),
      note: String(note || ""),

      clinicLat: isValidLatLng(lat, lng) ? lat : null,
      clinicLng: isValidLatLng(lat, lng) ? lng : null,

      clinicPhone: s(clinicPhone),
      clinicName: s(clinicName),
      clinicAddress: s(clinicAddress),
    });

    let clinicMap = new Map();
    if (Clinic && cid) {
      clinicMap = await loadClinicMapByIds([cid]);
    }

    return res.json({
      ok: true,
      shift: normalizeShiftOutput(created.toObject(), clinicMap),
    });
  } catch (e) {
    return res.status(500).json({
      message: "createShift failed",
      error: e.message || String(e),
    });
  }
}

// GET /shifts
async function listShifts(req, res) {
  try {
    const role = s(req.user?.role);
    const tokenClinicId = s(req.user?.clinicId);
    const tokenStaffId = s(req.user?.staffId);
    const tokenUserId = s(req.user?.userId);

    const {
      clinicId = "",
      staffId = "",
      helperUserId = "",
      date = "",
      status = "",
    } = req.query || {};

    const q = {};

    // clinic filter
    if (role === "admin") {
      if (clinicId) {
        q.clinicId = s(clinicId);
      } else if (tokenClinicId) {
        // ✅ admin ในระบบนี้มักควรถูกผูกกับคลินิกตัวเอง
        q.clinicId = tokenClinicId;
      }
    } else {
      if (!tokenClinicId) {
        return res.status(401).json({ message: "clinicId missing in token" });
      }
      q.clinicId = tokenClinicId;
    }

    if (date) q.date = s(date);
    if (status) q.status = s(status);

    if (role === "admin") {
      // admin ดูได้ทั้งหมดในคลินิกตัวเอง และกรองเพิ่มได้
      if (staffId) q.staffId = s(staffId);
      if (helperUserId) q.helperUserId = s(helperUserId);
    } else if (role === "employee") {
      // employee ต้องใช้ staffId จาก token
      if (!tokenStaffId) {
        return res.status(403).json({ message: "staffId missing in token" });
      }
      q.staffId = tokenStaffId;
    } else if (role === "helper") {
      // helper ใช้ helperUserId เป็นหลัก
      if (tokenUserId) {
        q.helperUserId = tokenUserId;
      } else if (tokenStaffId) {
        // fallback legacy
        q.staffId = tokenStaffId;
      } else {
        return res.json({ ok: true, items: [] });
      }
    } else {
      return res.status(403).json({ message: "Forbidden" });
    }

    const rows = await Shift.find(q).sort({ date: -1, createdAt: -1 }).lean();

    let clinicMap = new Map();
    if (Clinic && rows.length) {
      const clinicIds = rows.map((r) => s(r.clinicId)).filter(Boolean);
      clinicMap = await loadClinicMapByIds(clinicIds);
    }

    const items = rows.map((r) => normalizeShiftOutput(r, clinicMap));

    return res.json({
      ok: true,
      items,
    });
  } catch (e) {
    return res.status(500).json({
      message: "listShifts failed",
      error: e.message || String(e),
    });
  }
}

// PATCH /shifts/:id/status
async function updateShiftStatus(req, res) {
  try {
    if (!mustBeAdmin(req, res)) return;

    const id = s(req.params.id || "");
    if (!id) return res.status(400).json({ message: "id required" });

    const shift = await Shift.findById(id);
    if (!shift) {
      return res.status(404).json({ message: "Shift not found" });
    }

    if (req.body?.status !== undefined) {
      shift.status = s(req.body.status);
    }
    if (req.body?.minutesLate !== undefined) {
      shift.minutesLate = Number(req.body.minutesLate || 0);
    }

    await shift.save();

    let clinicMap = new Map();
    if (Clinic && s(shift.clinicId)) {
      clinicMap = await loadClinicMapByIds([s(shift.clinicId)]);
    }

    return res.json({
      ok: true,
      shift: normalizeShiftOutput(shift.toObject(), clinicMap),
    });
  } catch (e) {
    return res.status(500).json({
      message: "updateShiftStatus failed",
      error: e.message || String(e),
    });
  }
}

// DELETE /shifts/:id
async function deleteShift(req, res) {
  try {
    if (!mustBeAdmin(req, res)) return;

    const id = s(req.params.id || "");
    if (!id) return res.status(400).json({ message: "id required" });

    await Shift.findByIdAndDelete(id);

    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({
      message: "deleteShift failed",
      error: e.message || String(e),
    });
  }
}

module.exports = {
  createShift,
  listShifts,
  updateShiftStatus,
  deleteShift,
};