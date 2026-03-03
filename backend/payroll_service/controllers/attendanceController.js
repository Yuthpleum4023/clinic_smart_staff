// backend/payroll_service/controllers/attendanceController.js
const mongoose = require("mongoose");
const AttendanceSession = require("../models/AttendanceSession");
const Shift = require("../models/Shift");
const ClinicPolicy = require("../models/ClinicPolicy");
const Overtime = require("../models/Overtime");
const { getEmployeeByUserId } = require("../utils/staffClient");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = null) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function isHHmm(v) {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(String(v || "").trim());
}

function isYmd(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(v || "").trim());
}

function clampMinutes(m) {
  const x = Math.max(0, Math.floor(Number(m || 0)));
  return Number.isFinite(x) ? x : 0;
}

function monthKeyFromYmd(workDate) {
  const d = s(workDate);
  return isYmd(d) ? d.slice(0, 7) : "";
}

// Thailand fixed offset; shift date/start/end are local
function makeLocalDateTime(dateYmd, timeHHmm) {
  // returns Date in UTC based on +07:00 offset
  return new Date(`${dateYmd}T${timeHHmm}:00+07:00`);
}

function minutesDiff(a, b) {
  // b - a in minutes
  return Math.floor((b.getTime() - a.getTime()) / 60000);
}

function floorToStepMinutes(minutes, step) {
  if (!step || step <= 0) return minutes;
  return Math.floor(minutes / step) * step;
}

function roundOtMinutes(minutes, rounding) {
  const m = clampMinutes(minutes);
  const r = s(rounding);

  if (r === "NONE") return m;
  if (r === "15MIN") return floorToStepMinutes(m, 15);
  if (r === "30MIN") return floorToStepMinutes(m, 30);
  if (r === "HOUR") return floorToStepMinutes(m, 60);
  return floorToStepMinutes(m, 15);
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * ✅ PRINCIPAL (รองรับ helper ไม่มี staffId)
 * - ถ้ามี staffId => principalId = staffId, principalType="staff"
 * - ถ้าไม่มี staffId => principalId = userId, principalType="user"
 *
 * ✅ IMPORTANT:
 * - AttendanceSession.staffId = เก็บ "staffId จริง" เท่านั้น (อาจเป็น "")
 * - ไม่เอา usr_ ไปยัดใน staffId แล้ว
 */
function getPrincipal(req) {
  const clinicId = s(req.user?.clinicId);
  const role = s(req.user?.role);
  const userId = s(req.user?.userId);
  const staffId = s(req.user?.staffId);

  const principalId = staffId || userId;
  const principalType = staffId ? "staff" : "user";

  return { clinicId, role, userId, staffId, principalId, principalType };
}

async function getOrCreatePolicy(clinicId, userId) {
  let p = await ClinicPolicy.findOne({ clinicId });
  if (!p) {
    p = await ClinicPolicy.create({
      clinicId,
      timezone: "Asia/Bangkok",
      requireBiometric: true,
      requireLocation: false,
      geoRadiusMeters: 200,
      graceLateMinutes: 10,

      otRule: "AFTER_CLOCK_TIME",
      regularHoursPerDay: 8,

      otClockTime: "18:00",
      fullTimeOtClockTime: "18:00",
      partTimeOtClockTime: "18:00",

      otStartAfterMinutes: 0,
      otRounding: "15MIN",
      otMultiplier: 1.5,
      holidayMultiplier: 2.0,
      weekendAllDayOT: false,
      version: 1,
      updatedBy: s(userId),
    });
  }
  return p;
}

/**
 * ✅ Load shift for session (รองรับ helperUserId)
 * priority:
 *  1) shiftId (ObjectId) -> findById
 *  2) if staffId exists -> findOne clinicId + staffId + date
 *  3) else -> findOne clinicId + helperUserId(userId) + date
 */
async function loadShiftForSession({ clinicId, staffId, userId, workDate, shiftId }) {
  if (shiftId && mongoose.Types.ObjectId.isValid(String(shiftId))) {
    const sh = await Shift.findById(shiftId).lean();
    return sh || null;
  }

  const cid = s(clinicId);
  const date = s(workDate);
  const sid = s(staffId);
  const uid = s(userId);

  if (sid) {
    const sh = await Shift.findOne({ clinicId: cid, staffId: sid, date })
      .sort({ createdAt: -1 })
      .lean();
    return sh || null;
  }

  if (uid) {
    const sh = await Shift.findOne({ clinicId: cid, helperUserId: uid, date })
      .sort({ createdAt: -1 })
      .lean();
    return sh || null;
  }

  return null;
}

function computeLateMinutes(policy, shift, checkInAt) {
  if (!shift) return 0;
  if (!isYmd(shift.date) || !isHHmm(shift.start)) return 0;

  const shiftStart = makeLocalDateTime(shift.date, shift.start);
  const diff = minutesDiff(shiftStart, checkInAt);
  const late = Math.max(0, diff - clampMinutes(policy.graceLateMinutes));
  return clampMinutes(late);
}

function computeWorkedMinutes(checkInAt, checkOutAt) {
  if (!checkInAt || !checkOutAt) return 0;
  const m = minutesDiff(checkInAt, checkOutAt);
  return clampMinutes(m);
}

function computeOtMinutes(policy, shift, checkInAt, checkOutAt) {
  if (!checkInAt || !checkOutAt) return 0;

  const rule = s(policy.otRule);

  if (rule === "AFTER_SHIFT_END") {
    if (!shift || !isYmd(shift.date) || !isHHmm(shift.end)) return 0;

    const startLocal = isHHmm(shift.start) ? makeLocalDateTime(shift.date, shift.start) : null;
    let endLocal = makeLocalDateTime(shift.date, shift.end);

    if (startLocal && endLocal.getTime() <= startLocal.getTime()) {
      endLocal = new Date(endLocal.getTime() + 24 * 60 * 60000);
    }

    const otStartAt = new Date(
      endLocal.getTime() + clampMinutes(policy.otStartAfterMinutes) * 60000
    );

    const raw = Math.max(0, minutesDiff(otStartAt, checkOutAt));
    return roundOtMinutes(raw, policy.otRounding);
  }

  if (rule === "AFTER_CLOCK_TIME") {
    const ymd = shift?.date && isYmd(shift.date) ? shift.date : null;
    const baseDate = ymd || null;
    if (!baseDate) return 0;

    const clock = isHHmm(policy.otClockTime) ? policy.otClockTime : "18:00";
    const clockAt = makeLocalDateTime(baseDate, clock);
    const otStartAt = new Date(
      clockAt.getTime() + clampMinutes(policy.otStartAfterMinutes) * 60000
    );

    const raw = Math.max(0, minutesDiff(otStartAt, checkOutAt));
    return roundOtMinutes(raw, policy.otRounding);
  }

  if (rule === "AFTER_DAILY_HOURS") {
    const worked = computeWorkedMinutes(checkInAt, checkOutAt);
    const regular = clampMinutes(Number(policy.regularHoursPerDay || 8) * 60);
    const raw = Math.max(0, worked - regular);
    return roundOtMinutes(raw, policy.otRounding);
  }

  return 0;
}

// helper: normalize employmentType from staff_service (robust)
function normalizeEmploymentType(v) {
  const t = s(v).toLowerCase();
  if (!t) return "";
  if (t === "fulltime" || t === "full_time" || t === "full-time" || t === "ft") return "fullTime";
  if (t === "parttime" || t === "part_time" || t === "part-time" || t === "pt") return "partTime";
  return s(v);
}

// helper: select OT clock time by employee type (fullTime/partTime)
function pickOtClockByType(policy, empTypeRaw) {
  const empType = normalizeEmploymentType(empTypeRaw);
  const legacy = isHHmm(policy?.otClockTime) ? policy.otClockTime : "18:00";

  if (empType === "fullTime") {
    const v = s(policy?.fullTimeOtClockTime);
    return isHHmm(v) ? v : legacy;
  }
  if (empType === "partTime") {
    const v = s(policy?.partTimeOtClockTime);
    return isHHmm(v) ? v : legacy;
  }
  return legacy;
}

// ======================================================
// POST /attendance/check-in
// body: { workDate, shiftId?, method?, biometricVerified?, deviceId?, lat?, lng?, note? }
// ✅ รองรับ employee + helper (helper ไม่มี staffId ก็ได้)
// ======================================================
async function checkIn(req, res) {
  try {
    const { clinicId, userId, staffId, principalId, principalType } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    }
    if (!principalId) {
      return res.status(401).json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const workDate = s(req.body?.workDate);
    const shiftId = req.body?.shiftId || null;

    if (!isYmd(workDate)) {
      return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);

    const method = s(req.body?.method) || "biometric";
    const biometricVerified = !!req.body?.biometricVerified;
    if (policy.requireBiometric && !biometricVerified) {
      return res.status(400).json({ ok: false, message: "Biometric required" });
    }

    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);

    const shift = await loadShiftForSession({
      clinicId,
      staffId, // may be ""
      userId, // helperUserId fallback
      workDate,
      shiftId,
    });

    // ✅ Distance rule: ใช้ policy.geoRadiusMeters (หน่วยเมตร) เมื่อ requireLocation=true
    if (policy.requireLocation) {
      if (!(Number.isFinite(lat) && Number.isFinite(lng))) {
        return res.status(400).json({ ok: false, message: "Location required" });
      }

      const refLat = shift?.clinicLat;
      const refLng = shift?.clinicLng;

      if (Number.isFinite(refLat) && Number.isFinite(refLng)) {
        const dist = haversineMeters(refLat, refLng, lat, lng);
        const radius = Number(policy.geoRadiusMeters || 200);
        if (dist > radius) {
          return res.status(400).json({
            ok: false,
            message: "Outside allowed radius",
            distanceMeters: Math.round(dist),
            radiusMeters: radius,
          });
        }
      }
    }

    // ✅ prevent duplicate open session (by principalId)
    const existing = await AttendanceSession.findOne({
      clinicId,
      principalId,
      workDate,
      status: "open",
    });

    if (existing) {
      return res.status(409).json({
        ok: false,
        message: "Already checked-in (open session exists)",
        session: existing,
      });
    }

    const checkInAt = new Date();
    const lateMinutes = computeLateMinutes(policy, shift, checkInAt);

    const created = await AttendanceSession.create({
      clinicId,

      // ✅ identity fields
      principalId,
      principalType,

      // ✅ staffId แยกจริง (เก็บเฉพาะ stf_... ถ้าไม่มีให้ว่าง)
      staffId: staffId || "",

      // ✅ userId เก็บเสมอ (usr_...) ถ้า token ไม่มี (rare) ให้เป็น ""
      userId: userId || "",

      shiftId: shift ? shift._id : null,
      workDate,
      checkInAt,
      checkInMethod: method === "manual" ? "manual" : "biometric",
      biometricVerifiedIn: biometricVerified,
      deviceId: s(req.body?.deviceId),
      inLat: Number.isFinite(lat) ? lat : null,
      inLng: Number.isFinite(lng) ? lng : null,
      note: s(req.body?.note),

      lateMinutes,
      policyVersion: Number(policy.version || 0),
    });

    return res.status(201).json({ ok: true, session: created });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "check-in failed", error: e.message });
  }
}

// ======================================================
// POST /attendance/check-out (recommended)
// POST /attendance/:id/check-out (backward compatible)
// ✅ รองรับ employee + helper (helper ไม่มี staffId ก็ได้)
// ======================================================
async function checkOut(req, res) {
  try {
    const { clinicId, userId, staffId, principalId, principalType } = getPrincipal(req);

    if (!clinicId) {
      return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    }
    if (!principalId) {
      return res.status(401).json({ ok: false, message: "Missing userId/staffId in token" });
    }

    const id = s(req.params?.id);

    let session = null;
    if (id) {
      session = await AttendanceSession.findById(id);
      if (!session) return res.status(404).json({ ok: false, message: "Session not found" });
    } else {
      session = await AttendanceSession.findOne({
        clinicId,
        principalId,
        status: "open",
      }).sort({ checkInAt: -1 });

      if (!session) {
        return res.status(404).json({ ok: false, message: "No open session to check-out" });
      }
    }

    // ✅ Must be same clinic
    if (s(session.clinicId) !== clinicId) {
      return res.status(403).json({ ok: false, message: "Forbidden (cross-clinic session)" });
    }

    // ✅ Must be owner principal
    if (s(session.principalId) !== principalId) {
      return res.status(403).json({ ok: false, message: "Forbidden (not your session)" });
    }

    if (session.status !== "open") {
      return res.status(409).json({ ok: false, message: "Session is not open" });
    }

    const policy = await getOrCreatePolicy(s(session.clinicId), userId || principalId);

    const method = s(req.body?.method) || "biometric";
    const biometricVerified = !!req.body?.biometricVerified;
    if (policy.requireBiometric && !biometricVerified) {
      return res.status(400).json({ ok: false, message: "Biometric required" });
    }

    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);

    const shift = await loadShiftForSession({
      clinicId: s(session.clinicId),
      staffId: s(session.staffId) || staffId, // best effort
      userId: s(session.userId) || userId || "",
      workDate: s(session.workDate),
      shiftId: session.shiftId,
    });

    if (policy.requireLocation) {
      if (!(Number.isFinite(lat) && Number.isFinite(lng))) {
        return res.status(400).json({ ok: false, message: "Location required" });
      }

      const refLat = shift?.clinicLat;
      const refLng = shift?.clinicLng;

      if (Number.isFinite(refLat) && Number.isFinite(refLng)) {
        const dist = haversineMeters(refLat, refLng, lat, lng);
        const radius = Number(policy.geoRadiusMeters || 200);
        if (dist > radius) {
          return res.status(400).json({
            ok: false,
            message: "Outside allowed radius",
            distanceMeters: Math.round(dist),
            radiusMeters: radius,
          });
        }
      }
    }

    const checkOutAt = new Date();

    // ✅ employee master (อาจ null สำหรับ helper marketplace)
    let emp = null;
    const ownerUserId = s(session.userId) || userId || "";
    if (ownerUserId) {
      try {
        emp = await getEmployeeByUserId(ownerUserId);
      } catch (_) {
        emp = null;
      }
    }

    const empType = normalizeEmploymentType(emp?.employmentType);
    const selectedClock = pickOtClockByType(policy, empType);

    const policyForOt = {
      ...(policy.toObject?.() ?? policy),
      otClockTime: selectedClock,
    };

    const workedMinutes = computeWorkedMinutes(session.checkInAt, checkOutAt);
    const otMinutes = computeOtMinutes(policyForOt, shift, session.checkInAt, checkOutAt);

    session.checkOutAt = checkOutAt;
    session.status = "closed";
    session.checkOutMethod = method === "manual" ? "manual" : "biometric";
    session.biometricVerifiedOut = biometricVerified;

    if (s(req.body?.deviceId)) session.deviceId = s(req.body?.deviceId);

    session.outLat = Number.isFinite(lat) ? lat : session.outLat;
    session.outLng = Number.isFinite(lng) ? lng : session.outLng;

    session.workedMinutes = workedMinutes;
    session.otMinutes = otMinutes;
    session.policyVersion = Number(policy.version || session.policyVersion || 0);

    if (s(req.body?.note)) session.note = s(req.body?.note);

    await session.save();

    // ======================================================
    // ✅ HOOK: create/update Overtime record (pending)
    // - ใช้ principalId เป็น key หลักเสมอ (employee/helper ใช้ได้เหมือนกัน)
    // - staffId เก็บเฉพาะ stf_ (ถ้าไม่มีให้ "")
    // ======================================================
    try {
      const clinicIdOfSession = s(session.clinicId);
      const workDate = s(session.workDate);
      const monthKey = monthKeyFromYmd(workDate);

      const otMul = Number(
        emp?.otMultiplierNormal || policyForOt.otMultiplier || policy.otMultiplier || 1.5
      );
      const mul = Number.isFinite(otMul) && otMul > 0 ? otMul : 1.5;

      const principalIdForOt = s(session.principalId) || principalId;
      const principalTypeForOt = s(session.principalType) || principalType || (s(session.staffId) ? "staff" : "user");
      const staffIdForOt = s(session.staffId); // stf_... or ""

      if (clampMinutes(otMinutes) > 0 && monthKey) {
        await Overtime.updateOne(
          { clinicId: clinicIdOfSession, attendanceSessionId: session._id },
          {
            $set: {
              clinicId: clinicIdOfSession,

              // ✅ NEW
              principalId: principalIdForOt,
              principalType: principalTypeForOt,

              // ✅ optional
              staffId: staffIdForOt,
              userId: ownerUserId || "",

              workDate,
              monthKey,
              minutes: clampMinutes(otMinutes),
              multiplier: mul,
              status: "pending",
              source: "attendance",
              attendanceSessionId: session._id,
              note: s(session.note),
            },
            $setOnInsert: {
              approvedBy: "",
              approvedAt: null,
              rejectedBy: "",
              rejectedAt: null,
              rejectReason: "",
              lockedBy: "",
              lockedAt: null,
              lockedMonth: "",
            },
          },
          { upsert: true }
        );
      } else {
        await Overtime.deleteOne({ clinicId: clinicIdOfSession, attendanceSessionId: session._id });
      }
    } catch (e) {
      console.log("❌ Overtime hook failed:", e.message);
    }

    return res.json({
      ok: true,
      session,
      otMeta: {
        employmentType: empType || null,
        selectedClock,
        rule: s(policyForOt.otRule),
        otMinutes,
      },
    });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "check-out failed", error: e.message });
  }
}

// ======================================================
// GET /attendance/me?dateFrom=yyyy-MM-dd&dateTo=yyyy-MM-dd
// ✅ รองรับ helper ไม่มี staffId (ใช้ principalId)
// ======================================================
async function listMySessions(req, res) {
  try {
    const { clinicId, principalId } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!principalId)
      return res.status(401).json({ ok: false, message: "Missing userId/staffId in token" });

    const dateFrom = s(req.query?.dateFrom);
    const dateTo = s(req.query?.dateTo);

    const q = { clinicId, principalId };
    if (isYmd(dateFrom) && isYmd(dateTo)) q.workDate = { $gte: dateFrom, $lte: dateTo };

    const items = await AttendanceSession.find(q).sort({ checkInAt: -1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "list failed", error: e.message });
  }
}

// ======================================================
// ✅ Admin-only report
// GET /attendance/clinic?workDate=yyyy-MM-dd&staffId=...
// NOTE:
// - staffId param นี้: รองรับทั้ง staffId จริง และ principalId เพื่อ backward compatible
// ======================================================
async function listClinicSessions(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });

    if (role !== "admin") {
      return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });
    }

    const workDate = s(req.query?.workDate);
    const staffIdOrPrincipal = s(req.query?.staffId);

    const q = { clinicId };
    if (isYmd(workDate)) q.workDate = workDate;

    if (staffIdOrPrincipal) {
      q.$or = [{ staffId: staffIdOrPrincipal }, { principalId: staffIdOrPrincipal }];
    }

    const items = await AttendanceSession.find(q).sort({ checkInAt: -1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "list clinic failed", error: e.message });
  }
}

// ======================================================
// GET /attendance/me-preview?workDate=yyyy-MM-dd
// ✅ รองรับ helper (ไม่มี staffId ก็ได้)
// - OT count: approved only
// ======================================================
async function myDayPreview(req, res) {
  try {
    const { clinicId, principalId, userId } = getPrincipal(req);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!principalId)
      return res.status(401).json({ ok: false, message: "Missing userId/staffId in token" });

    const workDate = s(req.query?.workDate);
    if (!isYmd(workDate)) {
      return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId || principalId);

    const sessions = await AttendanceSession.find({
      clinicId,
      principalId,
      workDate,
      status: "closed",
    }).lean();

    const workedMinutes = sessions.reduce((sum, x) => sum + clampMinutes(x.workedMinutes), 0);
    const otMinutesRawFromSessions = sessions.reduce((sum, x) => sum + clampMinutes(x.otMinutes), 0);

    // ✅ NEW: query by principalId
    const approvedOt = await Overtime.find({
      clinicId,
      principalId,
      workDate,
      status: "approved",
    }).lean();

    const otMinutesApproved = approvedOt.reduce((sum, x) => sum + clampMinutes(x.minutes), 0);

    // employee master (may be null for helper marketplace)
    let emp = null;
    const ownerUserId = userId || "";
    if (ownerUserId) {
      try {
        emp = await getEmployeeByUserId(ownerUserId);
      } catch (_) {
        emp = null;
      }
    }

    const type = normalizeEmploymentType(emp?.employmentType);
    const hoursPerDay = Number(emp?.hoursPerDay || 8);
    const daysPerMonth = Number(emp?.workingDaysPerMonth || 26);

    let baseHourly = Number(emp?.hourlyRate || 0);
    if (type === "fullTime") {
      const monthly = Number(emp?.monthlySalary || 0);
      const denom = Math.max(1, daysPerMonth * hoursPerDay);
      baseHourly = monthly > 0 ? monthly / denom : 0;
    }

    const normalMinutes = Math.max(0, workedMinutes - otMinutesApproved);
    const normalPay = (normalMinutes / 60) * baseHourly;

    const otMul = Number(emp?.otMultiplierNormal || policy.otMultiplier || 1.5);
    const otPay = (otMinutesApproved / 60) * baseHourly * otMul;

    return res.json({
      ok: true,
      workDate,
      employee: emp || null,
      principal: {
        principalId,
        staffId: s(req.user?.staffId),
        userId: s(req.user?.userId),
      },
      policy: {
        otRule: policy.otRule,
        otRounding: policy.otRounding,
        otMultiplier: policy.otMultiplier,
        version: policy.version,
        fullTimeOtClockTime: policy.fullTimeOtClockTime,
        partTimeOtClockTime: policy.partTimeOtClockTime,
        otClockTime: policy.otClockTime,
      },
      summary: {
        workedMinutes,
        otMinutesApproved,
        otMinutesRawFromSessions,
        baseHourly,
        normalPay,
        otPay,
        totalPay: normalPay + otPay,
      },
      sessions,
      approvedOtRecords: approvedOt,
    });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "preview failed", error: e.message });
  }
}

module.exports = {
  checkIn,
  checkOut,
  listMySessions,
  listClinicSessions,
  myDayPreview,
};