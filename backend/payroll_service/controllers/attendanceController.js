// backend/payroll_service/controllers/attendanceController.js
const mongoose = require("mongoose");
const AttendanceSession = require("../models/AttendanceSession");
const Shift = require("../models/Shift");
const ClinicPolicy = require("../models/ClinicPolicy");
const Overtime = require("../models/Overtime"); // ✅ NEW
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
  // default
  return floorToStepMinutes(m, 15);
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  // minimal distance check for geoRadius
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

async function getOrCreatePolicy(clinicId, userId) {
  let p = await ClinicPolicy.findOne({ clinicId });
  if (!p) {
    // ✅ Default aligned with new requirement: OT starts after clock time
    // ✅ Include separated clock times for full/part (fallback to legacy otClockTime)
    p = await ClinicPolicy.create({
      clinicId,
      timezone: "Asia/Bangkok",
      requireBiometric: true,
      requireLocation: false,
      geoRadiusMeters: 200,
      graceLateMinutes: 10,

      // ✅ changed default
      otRule: "AFTER_CLOCK_TIME",
      regularHoursPerDay: 8,

      // legacy + new fields
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

async function loadShiftForSession({ clinicId, staffId, workDate, shiftId }) {
  // priority: shiftId
  if (shiftId && mongoose.Types.ObjectId.isValid(String(shiftId))) {
    const sh = await Shift.findById(shiftId).lean();
    return sh || null;
  }

  // fallback: find shift by clinicId+staffId+date
  const sh = await Shift.findOne({
    clinicId: s(clinicId),
    staffId: s(staffId),
    date: s(workDate),
  })
    .sort({ createdAt: -1 })
    .lean();

  return sh || null;
}

function computeLateMinutes(policy, shift, checkInAt) {
  if (!shift) return 0;
  if (!isYmd(shift.date) || !isHHmm(shift.start)) return 0;

  const shiftStart = makeLocalDateTime(shift.date, shift.start);
  const diff = minutesDiff(shiftStart, checkInAt); // checkIn - shiftStart
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

  // 1) AFTER_SHIFT_END: OT after shift end (+ otStartAfterMinutes)
  if (rule === "AFTER_SHIFT_END") {
    if (!shift || !isYmd(shift.date) || !isHHmm(shift.end)) return 0;

    const startLocal = isHHmm(shift.start)
      ? makeLocalDateTime(shift.date, shift.start)
      : null;
    let endLocal = makeLocalDateTime(shift.date, shift.end);

    // handle cross-midnight: end earlier than start => next day
    if (startLocal && endLocal.getTime() <= startLocal.getTime()) {
      endLocal = new Date(endLocal.getTime() + 24 * 60 * 60000);
    }

    const otStartAt = new Date(
      endLocal.getTime() + clampMinutes(policy.otStartAfterMinutes) * 60000
    );

    const raw = Math.max(0, minutesDiff(otStartAt, checkOutAt));
    return roundOtMinutes(raw, policy.otRounding);
  }

  // 2) AFTER_CLOCK_TIME: OT after a clock time (workDate + otClockTime) (+ otStartAfterMinutes)
  if (rule === "AFTER_CLOCK_TIME") {
    const ymd = shift?.date && isYmd(shift.date) ? shift.date : null;
    const baseDate = ymd || null;

    // if no shift, require workDate (MVP)
    if (!baseDate) return 0;

    const clock = isHHmm(policy.otClockTime) ? policy.otClockTime : "18:00";
    const clockAt = makeLocalDateTime(baseDate, clock);
    const otStartAt = new Date(
      clockAt.getTime() + clampMinutes(policy.otStartAfterMinutes) * 60000
    );

    const raw = Math.max(0, minutesDiff(otStartAt, checkOutAt));
    return roundOtMinutes(raw, policy.otRounding);
  }

  // 3) AFTER_DAILY_HOURS: OT after hoursPerDay (MVP uses policy.regularHoursPerDay)
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
  if (t === "fulltime" || t === "full_time" || t === "full-time" || t === "ft")
    return "fullTime";
  if (t === "parttime" || t === "part_time" || t === "part-time" || t === "pt")
    return "partTime";
  // if already in camel
  if (t === "fulltime") return "fullTime";
  if (t === "parttime") return "partTime";
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
// ======================================================
async function checkIn(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const staffId = s(req.user?.staffId);
    const userId = s(req.user?.userId);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!staffId)
      return res.status(400).json({ ok: false, message: "Missing staffId in token" });

    const workDate = s(req.body?.workDate);
    const shiftId = req.body?.shiftId || null;

    if (!isYmd(workDate)) {
      return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });
    }

    const policy = await getOrCreatePolicy(clinicId, userId);

    // policy: biometric required
    const method = s(req.body?.method) || "biometric";
    const biometricVerified = !!req.body?.biometricVerified;

    if (policy.requireBiometric && !biometricVerified) {
      return res.status(400).json({ ok: false, message: "Biometric required" });
    }

    // policy: location required (MVP: compare with shift clinicLat/lng if exists)
    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);

    let shift = await loadShiftForSession({ clinicId, staffId, workDate, shiftId });

    if (policy.requireLocation) {
      if (!(Number.isFinite(lat) && Number.isFinite(lng))) {
        return res.status(400).json({ ok: false, message: "Location required" });
      }

      const refLat = shift?.clinicLat;
      const refLng = shift?.clinicLng;

      if (Number.isFinite(refLat) && Number.isFinite(refLng)) {
        const dist = haversineMeters(refLat, refLng, lat, lng);
        if (dist > Number(policy.geoRadiusMeters || 200)) {
          return res.status(400).json({
            ok: false,
            message: "Outside allowed radius",
            distanceMeters: Math.round(dist),
            radiusMeters: Number(policy.geoRadiusMeters || 200),
          });
        }
      }
    }

    // prevent duplicate open session
    const existing = await AttendanceSession.findOne({
      clinicId,
      staffId,
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

    // compute late if we have shift
    const checkInAt = new Date();
    const lateMinutes = computeLateMinutes(policy, shift, checkInAt);

    const created = await AttendanceSession.create({
      clinicId,
      staffId,
      userId,
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
// POST /attendance/check-out   (NEW recommended)
// POST /attendance/:id/check-out (backward compatible)
//
// body: { method?, biometricVerified?, deviceId?, lat?, lng?, note? }
// ======================================================
async function checkOut(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const staffId = s(req.user?.staffId);
    const userId = s(req.user?.userId);

    if (!clinicId)
      return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!staffId)
      return res.status(400).json({ ok: false, message: "Missing staffId in token" });

    // ✅ Premium rule: employee self checkout only (canonical role)
    // routes layer already enforces requireRole(["employee"]), but keep server-side safety:
    const role = s(req.user?.role);
    if (role && role !== "employee") {
      return res.status(403).json({ ok: false, message: "Forbidden (employee only)" });
    }

    const id = s(req.params?.id);

    // ✅ If no :id provided -> find active open session of this staff in this clinic
    let session = null;

    if (id) {
      session = await AttendanceSession.findById(id);
      if (!session) return res.status(404).json({ ok: false, message: "Session not found" });
    } else {
      session = await AttendanceSession.findOne({
        clinicId,
        staffId,
        status: "open",
      }).sort({ checkInAt: -1 });

      if (!session) {
        return res.status(404).json({
          ok: false,
          message: "No open session to check-out",
        });
      }
    }

    // ✅ Must be same clinic (anti-abuse)
    if (s(session.clinicId) !== clinicId) {
      return res.status(403).json({ ok: false, message: "Forbidden (cross-clinic session)" });
    }

    // ✅ Must be owner staff (anti-abuse)
    if (s(session.staffId) !== staffId) {
      return res.status(403).json({ ok: false, message: "Forbidden (not your session)" });
    }

    if (session.status !== "open") {
      return res.status(409).json({ ok: false, message: "Session is not open" });
    }

    const policy = await getOrCreatePolicy(s(session.clinicId), userId);

    const method = s(req.body?.method) || "biometric";
    const biometricVerified = !!req.body?.biometricVerified;

    if (policy.requireBiometric && !biometricVerified) {
      return res.status(400).json({ ok: false, message: "Biometric required" });
    }

    const lat = n(req.body?.lat, null);
    const lng = n(req.body?.lng, null);

    // load shift (if any)
    const shift = await loadShiftForSession({
      clinicId: s(session.clinicId),
      staffId: s(session.staffId),
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
        if (dist > Number(policy.geoRadiusMeters || 200)) {
          return res.status(400).json({
            ok: false,
            message: "Outside allowed radius",
            distanceMeters: Math.round(dist),
            radiusMeters: Number(policy.geoRadiusMeters || 200),
          });
        }
      }
    }

    const checkOutAt = new Date();

    // ✅ IMPORTANT:
    // pick OT clock time by employee type (use session.userId, not req.user.userId)
    let emp = null;
    const ownerUserId = s(session.userId);
    if (ownerUserId) {
      try {
        emp = await getEmployeeByUserId(ownerUserId);
      } catch (_) {
        emp = null;
      }
    }

    const empType = normalizeEmploymentType(emp?.employmentType); // "fullTime" | "partTime"
    const selectedClock = pickOtClockByType(policy, empType);

    // create a derived policy snapshot with otClockTime selected by type
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

    // update deviceId only if provided
    if (s(req.body?.deviceId)) session.deviceId = s(req.body?.deviceId);

    session.outLat = Number.isFinite(lat) ? lat : session.outLat;
    session.outLng = Number.isFinite(lng) ? lng : session.outLng;

    session.workedMinutes = workedMinutes;
    session.otMinutes = otMinutes;
    session.policyVersion = Number(policy.version || session.policyVersion || 0);

    if (s(req.body?.note)) session.note = s(req.body?.note);

    await session.save();

    // ======================================================
    // ✅ HOOK: create/update Overtime record (pending) from attendance
    // - one OT per attendance session (unique by attendanceSessionId)
    // - status starts as "pending" (admin approves later)
    // ======================================================
    try {
      const clinicIdOfSession = s(session.clinicId);
      const staffIdOfSession = s(session.staffId);
      const workDate = s(session.workDate);
      const monthKey = monthKeyFromYmd(workDate);

      // choose multiplier snapshot (employee override > clinic policy)
      const otMul = Number(
        emp?.otMultiplierNormal || policyForOt.otMultiplier || policy.otMultiplier || 1.5
      );
      const mul = Number.isFinite(otMul) && otMul > 0 ? otMul : 1.5;

      if (clampMinutes(otMinutes) > 0 && monthKey) {
        await Overtime.updateOne(
          { clinicId: clinicIdOfSession, attendanceSessionId: session._id },
          {
            $set: {
              clinicId: clinicIdOfSession,
              staffId: staffIdOfSession,
              userId: ownerUserId, // may be ""
              workDate,
              monthKey,
              minutes: clampMinutes(otMinutes),
              multiplier: mul,
              status: "pending",
              source: "attendance",
              attendanceSessionId: session._id,
              note: s(session.note),
            },
            // do NOT auto-approve
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
        // if OT becomes 0 (policy changed / test), remove leftover OT record for this session
        await Overtime.deleteOne({ clinicId: clinicIdOfSession, attendanceSessionId: session._id });
      }
    } catch (e) {
      console.log("❌ Overtime hook failed:", e.message);
      // do not fail check-out; attendance is still saved
    }

    return res.json({
      ok: true,
      session,
      // helpful debug for admin/testing (remove later if you want)
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
// ======================================================
async function listMySessions(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const staffId = s(req.user?.staffId);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!staffId) return res.status(400).json({ ok: false, message: "Missing staffId in token" });

    const dateFrom = s(req.query?.dateFrom);
    const dateTo = s(req.query?.dateTo);

    const q = { clinicId, staffId };
    if (isYmd(dateFrom) && isYmd(dateTo)) q.workDate = { $gte: dateFrom, $lte: dateTo };

    const items = await AttendanceSession.find(q).sort({ checkInAt: -1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "list failed", error: e.message });
  }
}

// ======================================================
// GET /attendance/clinic?workDate=yyyy-MM-dd&staffId=... (admin)
// ======================================================
async function listClinicSessions(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const role = s(req.user?.role);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (role !== "admin") return res.status(403).json({ ok: false, message: "Forbidden (admin only)" });

    const workDate = s(req.query?.workDate);
    const staffId = s(req.query?.staffId);

    const q = { clinicId };
    if (isYmd(workDate)) q.workDate = workDate;
    if (staffId) q.staffId = staffId;

    const items = await AttendanceSession.find(q).sort({ checkInAt: -1 }).lean();
    return res.json({ ok: true, items });
  } catch (e) {
    return res.status(500).json({ ok: false, message: "list clinic failed", error: e.message });
  }
}

// ======================================================
// (Optional) GET /attendance/me-with-pay?workDate=yyyy-MM-dd (MVP preview)
// ✅ NEW: เอา OT จาก Overtime.status="approved" เท่านั้น
// ======================================================
async function myDayPreview(req, res) {
  try {
    const clinicId = s(req.user?.clinicId);
    const staffId = s(req.user?.staffId);
    const userId = s(req.user?.userId);

    if (!clinicId) return res.status(401).json({ ok: false, message: "Missing clinicId in token" });
    if (!staffId) return res.status(400).json({ ok: false, message: "Missing staffId in token" });
    if (!userId) return res.status(400).json({ ok: false, message: "Missing userId in token" });

    const workDate = s(req.query?.workDate);
    if (!isYmd(workDate)) return res.status(400).json({ ok: false, message: "workDate required (yyyy-MM-dd)" });

    const policy = await getOrCreatePolicy(clinicId, userId);

    const sessions = await AttendanceSession.find({ clinicId, staffId, workDate, status: "closed" }).lean();

    // sum minutes
    const workedMinutes = sessions.reduce((sum, x) => sum + clampMinutes(x.workedMinutes), 0);

    // ✅ DEBUG ONLY (raw OT from sessions; not used for pay)
    const otMinutesRawFromSessions = sessions.reduce((sum, x) => sum + clampMinutes(x.otMinutes), 0);

    // ✅ NEW: OT must be APPROVED to count in pay preview
    const approvedOt = await Overtime.find({
      clinicId,
      staffId,
      workDate,
      status: "approved",
    }).lean();

    const otMinutesApproved = approvedOt.reduce((sum, x) => sum + clampMinutes(x.minutes), 0);

    // fetch employee master (fullTime/partTime + rates)
    const emp = await getEmployeeByUserId(userId);

    // pay (MVP):
    // - partTime: hourlyRate from employee.hourlyRate
    // - fullTime: derive hourly from monthlySalary / (workingDaysPerMonth * hoursPerDay)
    const type = normalizeEmploymentType(emp?.employmentType); // "fullTime" | "partTime"
    const hoursPerDay = Number(emp?.hoursPerDay || 8);
    const daysPerMonth = Number(emp?.workingDaysPerMonth || 26);

    let baseHourly = Number(emp?.hourlyRate || 0);
    if (type === "fullTime") {
      const monthly = Number(emp?.monthlySalary || 0);
      const denom = Math.max(1, daysPerMonth * hoursPerDay);
      baseHourly = monthly > 0 ? monthly / denom : 0;
    }

    // ✅ ใช้ approved OT เท่านั้น
    const normalMinutes = Math.max(0, workedMinutes - otMinutesApproved);
    const normalPay = (normalMinutes / 60) * baseHourly;

    // multiplier priority: employee override > clinic policy
    const otMul = Number(emp?.otMultiplierNormal || policy.otMultiplier || 1.5);
    const otPay = (otMinutesApproved / 60) * baseHourly * otMul;

    return res.json({
      ok: true,
      workDate,
      employee: emp || null,
      policy: {
        otRule: policy.otRule,
        otRounding: policy.otRounding,
        otMultiplier: policy.otMultiplier,
        version: policy.version,
        fullTimeOtClockTime: policy.fullTimeOtClockTime,
        partTimeOtClockTime: policy.partTimeOtClockTime,
        otClockTime: policy.otClockTime, // legacy
      },
      summary: {
        workedMinutes,
        otMinutesApproved, // ✅ ใช้ตัวนี้คำนวณเงิน
        otMinutesRawFromSessions, // ✅ เอาไว้เทียบว่าทำไมยังไม่เข้า payslip (ยัง pending)
        baseHourly,
        normalPay,
        otPay,
        totalPay: normalPay + otPay,
      },
      sessions,
      approvedOtRecords: approvedOt, // ✅ debug/admin view
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