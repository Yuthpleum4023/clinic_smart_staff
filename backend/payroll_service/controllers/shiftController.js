// payroll_service/controllers/shiftController.js
const mongoose = require("mongoose");
const Shift = require("../models/Shift");
const {
  s,
  numOrNull,
  isValidLatLng,
  buildDistancePayload,
  pickBestDistanceFromRow,
} = require("../utils/locationEngine");

// ✅ OPTIONAL: ถ้ามี models/Clinic.js จะดึงพิกัดคลินิกมาเติมให้
let Clinic = null;
try {
  Clinic = require("../models/Clinic");
} catch (_) {
  Clinic = null;
}

// -------------------- Helpers --------------------
function mustBeAdmin(req, res) {
  const role = s(req.user?.role);
  if (role !== "admin" && role !== "clinic_admin") {
    res.status(403).json({ message: "Forbidden (admin only)" });
    return false;
  }
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

function normalizeHelperUserIdInput(body = {}) {
  return s(
    body.helperUserId ||
      body.userId ||
      body.helperId ||
      body.assignedUserId ||
      body.acceptedHelperUserId ||
      body.selectedHelperUserId ||
      body.bookedHelperUserId
  );
}

function normalizeShiftOutput(
  row,
  clinicMap = new Map(),
  helperLocation = null
) {
  const out = {
    ...row,
    staffId: s(row.staffId),
    helperUserId: s(
      row.helperUserId ||
        row.userId ||
        row.helperId ||
        row.assignedUserId ||
        row.acceptedHelperUserId
    ),
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

  const distancePayload = buildDistancePayload(
    helperLocation,
    {
      lat: numOrNull(out.clinicLat),
      lng: numOrNull(out.clinicLng),
    }
  );

  if (distancePayload.distanceKm !== null) {
    out.distanceKm = distancePayload.distanceKm;
    out.distance_km = distancePayload.distance_km;
    out.distanceText = distancePayload.distanceText;
    out.distance_text = distancePayload.distance_text;
  } else {
    const fallback = pickBestDistanceFromRow(row);
    out.distanceKm = fallback.distanceKm;
    out.distance_km = fallback.distance_km;
    out.distanceText = fallback.distanceText;
    out.distance_text = fallback.distance_text;
  }

  return out;
}

function isHHmm(v) {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(s(v));
}

function makeLocalDateTime(dateYmd, timeHHmm) {
  return new Date(`${dateYmd}T${timeHHmm}:00+07:00`);
}

function getShiftRange(date, start, end) {
  if (!s(date) || !isHHmm(start) || !isHHmm(end)) return null;

  const startAt = makeLocalDateTime(date, start);
  let endAt = makeLocalDateTime(date, end);

  if (endAt.getTime() <= startAt.getTime()) {
    endAt = new Date(endAt.getTime() + 24 * 60 * 60000);
  }

  return { startAt, endAt };
}

function isOverlap(aStart, aEnd, bStart, bEnd) {
  return aStart.getTime() < bEnd.getTime() && bStart.getTime() < aEnd.getTime();
}

async function ensureNoShiftConflict({
  clinicId,
  date,
  start,
  end,
  staffId = "",
  helperUserId = "",
  excludeShiftId = "",
}) {
  const range = getShiftRange(date, start, end);
  if (!range) return null;

  const or = [];
  if (s(staffId)) or.push({ staffId: s(staffId) });
  if (s(helperUserId)) or.push({ helperUserId: s(helperUserId) });

  if (!or.length) return null;

  const q = {
    clinicId: s(clinicId),
    date: s(date),
    $or: or,
  };

  if (s(excludeShiftId) && mongoose.Types.ObjectId.isValid(String(excludeShiftId))) {
    q._id = { $ne: excludeShiftId };
  }

  const rows = await Shift.find(q).lean();

  for (const row of rows) {
    const existing = getShiftRange(row.date, row.start, row.end);
    if (!existing) continue;

    if (
      isOverlap(range.startAt, range.endAt, existing.startAt, existing.endAt)
    ) {
      return row;
    }
  }

  return null;
}

// -------------------- Controllers --------------------

// POST /shifts (admin)
async function createShift(req, res) {
  try {
    if (!mustBeAdmin(req, res)) return;

    const {
      clinicId,
      staffId,
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
    const hid = normalizeHelperUserIdInput(req.body || {});
    const d = s(date);
    const st = s(start);
    const en = s(end);

    if (!cid || (!sid && !hid) || !d || !st || !en) {
      return res.status(400).json({
        message:
          "clinicId + (staffId or helperUserId) + date + start + end required",
      });
    }

    const conflict = await ensureNoShiftConflict({
      clinicId: cid,
      date: d,
      start: st,
      end: en,
      staffId: sid,
      helperUserId: hid,
    });

    if (conflict) {
      return res.status(409).json({
        ok: false,
        code: "SHIFT_TIME_OVERLAP",
        message: "พบ shift ชนเวลากับรายการเดิม",
        conflictShiftId: String(conflict._id || ""),
        conflict,
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
      shift: normalizeShiftOutput(created.toObject(), clinicMap, null),
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
      helperLat = "",
      helperLng = "",
    } = req.query || {};

    const q = {};

    if (date) q.date = s(date);
    if (status) q.status = s(status);

    if (role === "admin" || role === "clinic_admin") {
      if (clinicId) {
        q.clinicId = s(clinicId);
      } else if (tokenClinicId) {
        q.clinicId = tokenClinicId;
      }

      if (staffId) q.staffId = s(staffId);
      if (helperUserId) q.helperUserId = s(helperUserId);
    } else if (role === "employee") {
      if (!tokenClinicId) {
        return res.status(401).json({ message: "clinicId missing in token" });
      }
      if (!tokenStaffId) {
        return res.status(403).json({ message: "staffId missing in token" });
      }

      q.clinicId = tokenClinicId;
      q.staffId = tokenStaffId;
    } else if (role === "helper") {
      if (tokenUserId) {
        q.helperUserId = tokenUserId;
      } else if (tokenStaffId) {
        q.staffId = tokenStaffId;
      } else {
        return res.json({ ok: true, items: [] });
      }

      if (clinicId) {
        q.clinicId = s(clinicId);
      }
    } else {
      return res.status(403).json({ message: "Forbidden" });
    }

    const rows = await Shift.find(q)
      .sort({ date: 1, start: 1, createdAt: -1 })
      .lean();

    let clinicMap = new Map();
    if (Clinic && rows.length) {
      const clinicIds = rows.map((r) => s(r.clinicId)).filter(Boolean);
      clinicMap = await loadClinicMapByIds(clinicIds);
    }

    const helperLocation = {
      lat: numOrNull(helperLat),
      lng: numOrNull(helperLng),
    };

    const items = rows.map((r) =>
      normalizeShiftOutput(r, clinicMap, helperLocation)
    );

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

    const nextStatus =
      req.body?.status !== undefined ? s(req.body.status) : s(shift.status);

    const nextMinutesLate =
      req.body?.minutesLate !== undefined
        ? Number(req.body.minutesLate || 0)
        : Number(shift.minutesLate || 0);

    const nextHelperUserId =
      req.body?.helperUserId !== undefined ||
      req.body?.userId !== undefined ||
      req.body?.helperId !== undefined ||
      req.body?.assignedUserId !== undefined ||
      req.body?.acceptedHelperUserId !== undefined
        ? normalizeHelperUserIdInput(req.body || {})
        : s(shift.helperUserId);

    const nextStaffId =
      req.body?.staffId !== undefined ? s(req.body.staffId) : s(shift.staffId);

    const nextDate =
      req.body?.date !== undefined ? s(req.body.date) : s(shift.date);

    const nextStart =
      req.body?.start !== undefined ? s(req.body.start) : s(shift.start);

    const nextEnd =
      req.body?.end !== undefined ? s(req.body.end) : s(shift.end);

    const conflict = await ensureNoShiftConflict({
      clinicId: s(shift.clinicId),
      date: nextDate,
      start: nextStart,
      end: nextEnd,
      staffId: nextStaffId,
      helperUserId: nextHelperUserId,
      excludeShiftId: id,
    });

    if (conflict) {
      return res.status(409).json({
        ok: false,
        code: "SHIFT_TIME_OVERLAP",
        message: "พบ shift ชนเวลากับรายการเดิม",
        conflictShiftId: String(conflict._id || ""),
        conflict,
      });
    }

    shift.status = nextStatus;
    shift.minutesLate = nextMinutesLate;
    shift.helperUserId = nextHelperUserId;
    shift.staffId = nextStaffId;
    shift.date = nextDate;
    shift.start = nextStart;
    shift.end = nextEnd;

    await shift.save();

    let clinicMap = new Map();
    if (Clinic && s(shift.clinicId)) {
      clinicMap = await loadClinicMapByIds([s(shift.clinicId)]);
    }

    return res.json({
      ok: true,
      shift: normalizeShiftOutput(shift.toObject(), clinicMap, null),
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