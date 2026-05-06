//
// payroll_service/controllers/payrollCloseController.js
//
// ✅ PRODUCTION — Backend-only Payroll Calculator
//
// GOAL:
// - Flutter ส่งเฉพาะ input / intent
// - Backend เป็นผู้คำนวณยอดเงินจริงทั้งหมด
//
// Flutter ส่งได้:
// - clinicId, employeeId, month
// - bonus, otherAllowance, otherDeduction
// - pvdEmployeeMonthly
// - taxMode
// - employeeUserId
// - regularWorkHours / regularWorkMinutes / workItems สำหรับ part-time ถ้ามี
// - grossBase เฉพาะ fallback compatibility ระหว่าง migration เท่านั้น
//
// Backend คำนวณเอง:
// - salary/grossBase จาก staff_service เป็นหลัก
// - ✅ Part-time normal wage จาก Attendance/check-in checkout ใน backend
// - OT จาก Overtime status=approved/locked เท่านั้น
// - OT รวมทุก source ที่ใช้คิดเงินเดือนได้:
//   attendance  = OT จากสแกน / check-in checkout
//   manual      = OT ที่ admin input เอง
//   manual_user = OT ที่ user ขอและ admin อนุมัติ
// - SSO จาก Clinic.socialSecurity
// - Tax/YTD จาก auth internal tax service
// - gross/net/display snapshot
//
// Backend จะไม่เชื่อค่าคำนวณจาก Flutter:
// - otPay จาก client ถูก ignore โดย default
// - ssoEmployeeMonthly จาก client ถูก ignore โดย default
// - grossMonthly/netPay/withheldTaxMonthly จาก client ไม่ถูกใช้
//
// ✅ Production patch:
// - full-time flow unchanged
// - part-time reads completed Attendance rows for regular work hours
// - part-time regular wage = attendance payable minutes * hourlyRate
// - part-time approved OT minutes are excluded from regular minutes to avoid double-pay
// - explicit include OT sources: attendance/manual/manual_user
// - include approved + locked OT records for recalculation safety
// - add OT breakdown by source for debugging
// - lock OT records after payroll close to prevent accidental mutation
// - recalculateClosedMonth() recalculates from latest approved/locked OT
//
// ✅ Production patch 2:
// - part-time Attendance query now supports assignment/shift/job references
// - if strict Attendance query cannot find rows, fallback searches clinic+month and deep-matches ids
// - supports old/migrated Attendance schemas with nested ids
// - avoids touching full-time salary/OT flow
//

const axios = require("axios");
const PayrollClose = require("../models/PayrollClose");
const TaxYTD = require("../models/TaxYTD");
const Overtime = require("../models/Overtime");
const Clinic = require("../models/Clinic");

// ✅ Attendance model used by attendanceController.js.
// Production source of truth for check-in / check-out rows.
let Attendance = null;
try {
  Attendance = require("../models/AttendanceSession");
} catch (e0) {
  try {
    Attendance = require("../models/Attendance");
  } catch (e1) {
    try {
      Attendance = require("../models/attendance");
    } catch (e2) {
      console.log("⚠️ Attendance model not loaded for payroll:", {
        AttendanceSession: e0?.message,
        Attendance: e1?.message,
        attendance: e2?.message,
      });
    }
  }
}

const { getEmployeeByStaffId } = require("../utils/staffClient");

// ================= constants =================
const PAYROLL_OT_SOURCES = ["attendance", "manual", "manual_user"];
const PAYROLL_OT_STATUSES = ["approved", "locked"];

// ================= errors =================
class HttpError extends Error {
  constructor(status, message, details = null) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

function throwHttp(status, message, details = null) {
  throw new HttpError(status, message, details);
}

// ================= helpers =================
function toNumber(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function clamp(n, a, b) {
  return Math.max(a, Math.min(b, n));
}

function clampMin0(v) {
  return Math.max(0, toNumber(v));
}

function safeStr(v) {
  return String(v || "").trim();
}

function baseUrlNoSlash(url) {
  return safeStr(url).replace(/\/$/, "");
}

function isYm(v) {
  return /^\d{4}-\d{2}$/.test(String(v || "").trim());
}

function monthToTaxYear(monthStr) {
  const y = Number(String(monthStr || "").slice(0, 4));
  return Number.isFinite(y) ? y : new Date().getFullYear();
}

function round2(v) {
  return Number(toNumber(v).toFixed(2));
}

function postJson(url, body, headers) {
  return axios.post(url, body, {
    headers,
    timeout: 15000,
    validateStatus: () => true,
  });
}

function hasOwn(obj, key) {
  return Object.prototype.hasOwnProperty.call(obj || {}, key);
}

function pickFirstPositiveNumber(obj, keys) {
  for (const k of keys) {
    const n = toNumber(obj?.[k]);
    if (n > 0) return round2(n);
  }
  return 0;
}

function pickFirstDefinedNumber(obj, keys) {
  for (const k of keys) {
    if (!hasOwn(obj, k)) continue;
    const n = Number(obj?.[k]);
    if (Number.isFinite(n)) return round2(n);
  }
  return null;
}

function normalizeRole(v) {
  const r = safeStr(v).toLowerCase();
  if (r === "clinicadmin") return "clinic_admin";
  return r;
}

function isAdminRole(role) {
  const r = normalizeRole(role);
  return r === "admin" || r === "clinic_admin";
}

function resolveMoneyInput({
  body,
  employee,
  oldDefaults,
  bodyKeys = [],
  employeeKeys = [],
  oldKeys = [],
  defaultValue = 0,
}) {
  const fromBody = pickFirstDefinedNumber(body, bodyKeys);
  if (fromBody !== null) return round2(clampMin0(fromBody));

  const fromEmployee = pickFirstDefinedNumber(employee, employeeKeys);
  if (fromEmployee !== null) return round2(clampMin0(fromEmployee));

  const fromOld = pickFirstDefinedNumber(oldDefaults, oldKeys);
  if (fromOld !== null) return round2(clampMin0(fromOld));

  return round2(clampMin0(defaultValue));
}

function normalizeEmploymentType(v) {
  const t = safeStr(v).toLowerCase();

  if (
    t === "parttime" ||
    t === "part-time" ||
    t === "part_time" ||
    t === "part time" ||
    t === "hourly"
  ) {
    return "parttime";
  }

  if (
    t === "fulltime" ||
    t === "full-time" ||
    t === "full_time" ||
    t === "full time" ||
    t === "monthly"
  ) {
    return "fulltime";
  }

  return "fulltime";
}

function resolvePartTimeHourlyFromEmployee(emp) {
  return pickFirstPositiveNumber(emp || {}, [
    "hourlyRate",
    "hourlyWage",
    "hourly_salary",
    "hourly_salary_rate",
    "wagePerHour",
    "ratePerHour",
  ]);
}

function resolveMonthlySalaryFromEmployee(emp) {
  return pickFirstPositiveNumber(emp || {}, [
    "baseSalary",
    "salary",
    "monthlySalary",
    "monthlyWage",
    "grossBase",
    "grossMonthly",
    "fixedSalary",
    "defaultSalary",
  ]);
}

function computeFullTimeOtBaseHourly(grossBase) {
  const salaryBase = round2(clampMin0(grossBase));
  if (salaryBase <= 0) return 0;
  return round2(salaryBase / 30 / 8);
}

function parseHHmm(v) {
  const s = safeStr(v);
  const parts = s.split(":");
  if (parts.length !== 2) return null;

  const h = Number(parts[0]);
  const m = Number(parts[1]);

  if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
  if (h < 0 || h > 23) return null;
  if (m < 0 || m > 59) return null;

  return { h, m };
}

function minutesBetween(startHHmm, endHHmm, breakMinutes = 0) {
  const s = parseHHmm(startHHmm);
  const e = parseHHmm(endHHmm);
  if (!s || !e) return 0;

  const startMin = s.h * 60 + s.m;
  let endMin = e.h * 60 + e.m;

  if (endMin < startMin) endMin += 24 * 60;

  const total =
    endMin - startMin - Math.max(0, Math.floor(toNumber(breakMinutes)));

  return total > 0 ? total : 0;
}

function extractRegularWorkMinutesFromItem(item) {
  if (!item || typeof item !== "object") return 0;

  const candidates = [
    item.regularWorkMinutes,
    item.workMinutes,
    item.minutes,
    item.totalMinutes,
  ];

  for (const v of candidates) {
    const n = Math.floor(toNumber(v));
    if (n > 0) return n;
  }

  const hoursCandidates = [
    item.regularWorkHours,
    item.workHours,
    item.hours,
    item.totalHours,
  ];

  for (const v of hoursCandidates) {
    const n = toNumber(v);
    if (n > 0) return Math.floor(n * 60);
  }

  const start = item.start || item.startTime || item.clockIn || item.checkIn;
  const end = item.end || item.endTime || item.clockOut || item.checkOut;
  const breakMinutes = item.breakMinutes || item.break_minutes || 0;

  return minutesBetween(start, end, breakMinutes);
}

function extractRegularWorkSummary(body) {
  const b = body || {};

  const minuteCandidates = [
    b.regularWorkMinutes,
    b.normalWorkMinutes,
    b.workMinutes,
    b.totalWorkMinutes,
  ];

  for (const v of minuteCandidates) {
    const n = Math.floor(toNumber(v));
    if (n > 0) {
      return {
        minutes: n,
        hours: round2(n / 60),
        source: "body.regularWorkMinutes",
      };
    }
  }

  const hourCandidates = [
    b.regularWorkHours,
    b.normalWorkHours,
    b.workHours,
    b.totalWorkHours,
  ];

  for (const v of hourCandidates) {
    const n = toNumber(v);
    if (n > 0) {
      return {
        minutes: Math.floor(n * 60),
        hours: round2(n),
        source: "body.regularWorkHours",
      };
    }
  }

  const arrays = [
    b.workItems,
    b.workEntries,
    b.regularWorkItems,
    b.regularWorkEntries,
  ];

  for (const arr of arrays) {
    if (!Array.isArray(arr) || arr.length === 0) continue;

    const minutes = arr.reduce(
      (sum, x) => sum + extractRegularWorkMinutesFromItem(x),
      0
    );

    if (minutes > 0) {
      return {
        minutes,
        hours: round2(minutes / 60),
        source: "body.workItems",
      };
    }
  }

  return {
    minutes: 0,
    hours: 0,
    source: "none",
  };
}

// ================= PART-TIME ATTENDANCE REGULAR WORK =================
// ✅ Production goal:
// - Part-time payroll must calculate normal wage from backend attendance
// - Fingerprint/check-in checkout creates Attendance rows
// - Payroll preview/close reads those rows directly
// - Full-time flow remains unchanged

function uniqueNonEmptyStrings(values) {
  return [...new Set((values || []).map(safeStr).filter(Boolean))];
}

function getByPath(obj, path) {
  if (!obj || !path) return undefined;

  const parts = String(path).split(".");
  let cur = obj;

  for (const p of parts) {
    if (cur == null || typeof cur !== "object") return undefined;
    cur = cur[p];
  }

  return cur;
}

function firstValueByPaths(obj, paths) {
  for (const p of paths || []) {
    const v = getByPath(obj, p);
    if (v !== undefined && v !== null && v !== "") return v;
  }
  return null;
}

function toDateOrNull(v) {
  if (!v) return null;

  if (v instanceof Date) {
    return Number.isFinite(v.getTime()) ? v : null;
  }

  const d = new Date(v);
  return Number.isFinite(d.getTime()) ? d : null;
}

function monthRangeBangkok(monthKey) {
  const s = safeStr(monthKey);
  const [yy, mm] = s.split("-").map((x) => Number(x));

  if (!Number.isFinite(yy) || !Number.isFinite(mm) || mm < 1 || mm > 12) {
    return null;
  }

  // Asia/Bangkok local month start 00:00 equals UTC previous day 17:00.
  const startDate = new Date(Date.UTC(yy, mm - 1, 1, -7, 0, 0, 0));
  const endDate = new Date(Date.UTC(yy, mm, 1, -7, 0, 0, 0));

  const lastDay = new Date(Date.UTC(yy, mm, 0)).getUTCDate();
  const startDay = `${s}-01`;
  const endDay = `${s}-${String(lastDay).padStart(2, "0")}`;

  return {
    startDate,
    endDate,
    startDay,
    endDay,
  };
}

function buildPayrollPersonIds({ employeeId, employee, body }) {
  return uniqueNonEmptyStrings([
    employeeId,

    body?.employeeUserId,
    body?.userId,
    body?.staffId,
    body?.workerId,
    body?.helperId,
    body?.principalId,

    // ✅ Part-time / marketplace / shift assignment ids
    body?.assignmentId,
    body?.workAssignmentId,
    body?.shiftNeedId,
    body?.clinicShiftNeedId,
    body?.shiftId,
    body?.jobId,
    body?.needId,
    body?.bookingId,
    body?.contractId,

    firstValueByPaths(body, ["assignment._id", "assignment.id"]),
    firstValueByPaths(body, ["shiftNeed._id", "shiftNeed.id"]),
    firstValueByPaths(body, ["shift._id", "shift.id"]),
    firstValueByPaths(body, ["job._id", "job.id"]),

    employee?._id,
    employee?.id,
    employee?.staffId,
    employee?.employeeId,
    employee?.userId,
    employee?.linkedUserId,
    employee?.linked_user_id,
    employee?.principalId,
    employee?.helperId,
    employee?.workerId,

    // ✅ Employee/staff service may return assignment references for part-time
    employee?.assignmentId,
    employee?.workAssignmentId,
    employee?.shiftNeedId,
    employee?.clinicShiftNeedId,
    employee?.shiftId,
    employee?.jobId,
    employee?.needId,
    employee?.bookingId,
    employee?.contractId,

    firstValueByPaths(employee, ["assignment._id", "assignment.id"]),
    firstValueByPaths(employee, ["shiftNeed._id", "shiftNeed.id"]),
    firstValueByPaths(employee, ["shift._id", "shift.id"]),
    firstValueByPaths(employee, ["job._id", "job.id"]),
  ]);
}

function buildAttendancePersonOr(personIds) {
  const ids = uniqueNonEmptyStrings(personIds);

  const fields = [
    // Normal payroll/staff/user identity fields
    "staffId",
    "employeeId",
    "userId",
    "principalId",
    "employeeUserId",
    "linkedUserId",
    "helperId",
    "workerId",
    "providerId",
    "assignedStaffId",
    "assignedUserId",
    "staffUserId",
    "memberId",
    "ownerId",
    "createdBy",

    // Nested staff/user objects
    "staff.id",
    "staff._id",
    "employee.id",
    "employee._id",
    "user.id",
    "user._id",
    "helper.id",
    "helper._id",
    "worker.id",
    "worker._id",
    "provider.id",
    "provider._id",

    // ✅ Part-time / marketplace / shift assignment identity fields
    "assignmentId",
    "workAssignmentId",
    "shiftNeedId",
    "clinicShiftNeedId",
    "shiftId",
    "jobId",
    "needId",
    "bookingId",
    "contractId",

    // Nested assignment/shift/job objects
    "assignment.id",
    "assignment._id",
    "workAssignment.id",
    "workAssignment._id",
    "shiftNeed.id",
    "shiftNeed._id",
    "clinicShiftNeed.id",
    "clinicShiftNeed._id",
    "shift.id",
    "shift._id",
    "job.id",
    "job._id",
    "need.id",
    "need._id",
    "booking.id",
    "booking._id",

    // Some schemas store refs under attendance/session/request
    "attendance.staffId",
    "attendance.employeeId",
    "attendance.userId",
    "attendance.helperId",
    "attendance.assignmentId",
    "attendance.shiftNeedId",
    "session.staffId",
    "session.employeeId",
    "session.userId",
    "session.helperId",
    "session.assignmentId",
    "session.shiftNeedId",
    "request.staffId",
    "request.employeeId",
    "request.userId",
    "request.helperId",
    "request.assignmentId",
    "request.shiftNeedId",
  ];

  const ors = [];

  for (const id of ids) {
    for (const f of fields) {
      ors.push({ [f]: id });
    }
  }

  return ors;
}

function buildAttendanceClinicOr(clinicId) {
  const cId = safeStr(clinicId);

  return [
    { clinicId: cId },
    { "clinic.id": cId },
    { "clinic._id": cId },
  ];
}

function buildAttendanceMonthOr(monthKey) {
  const mKey = safeStr(monthKey);
  const r = monthRangeBangkok(mKey);

  if (!r) return [{ monthKey: mKey }];

  return [
    { monthKey: mKey },
    { payrollMonth: mKey },
    { attendanceMonth: mKey },
    { workMonth: mKey },

    // String date fields: yyyy-MM-dd
    { workDate: { $gte: r.startDay, $lte: r.endDay } },
    { date: { $gte: r.startDay, $lte: r.endDay } },
    { attendanceDate: { $gte: r.startDay, $lte: r.endDay } },

    // Date fields
    { workDate: { $gte: r.startDate, $lt: r.endDate } },
    { date: { $gte: r.startDate, $lt: r.endDate } },
    { attendanceDate: { $gte: r.startDate, $lt: r.endDate } },

    // Actual time fields
    { checkInAt: { $gte: r.startDate, $lt: r.endDate } },
    { checkedInAt: { $gte: r.startDate, $lt: r.endDate } },
    { clockInAt: { $gte: r.startDate, $lt: r.endDate } },
    { inAt: { $gte: r.startDate, $lt: r.endDate } },
    { startAt: { $gte: r.startDate, $lt: r.endDate } },
    { createdAt: { $gte: r.startDate, $lt: r.endDate } },
  ];
}

function firstPositiveMinutesFromAttendance(row) {
  const minutePaths = [
    "regularWorkMinutes",
    "normalWorkMinutes",
    "workMinutes",
    "totalWorkMinutes",
    "totalMinutes",
    "workedMinutes",
    "durationMinutes",
    "minutes",
  ];

  for (const p of minutePaths) {
    const n = Math.floor(toNumber(getByPath(row, p)));
    if (n > 0) return n;
  }

  const hourPaths = [
    "regularWorkHours",
    "normalWorkHours",
    "workHours",
    "totalWorkHours",
    "totalHours",
    "workedHours",
    "durationHours",
    "hours",
  ];

  for (const p of hourPaths) {
    const n = toNumber(getByPath(row, p));
    if (n > 0) return Math.floor(n * 60);
  }

  return 0;
}

function extractAttendanceWorkedMinutes(row) {
  if (!row || typeof row !== "object") return 0;

  const precomputed = firstPositiveMinutesFromAttendance(row);
  if (precomputed > 0) return precomputed;

  const inRaw = firstValueByPaths(row, [
    "checkInAt",
    "checkedInAt",
    "clockInAt",
    "inAt",
    "startAt",
    "startTime",
    "checkInTime",
    "clockInTime",
    "timeIn",
    "checkIn.at",
    "clockIn.at",
  ]);

  const outRaw = firstValueByPaths(row, [
    "checkOutAt",
    "checkedOutAt",
    "clockOutAt",
    "outAt",
    "endAt",
    "endTime",
    "checkOutTime",
    "clockOutTime",
    "timeOut",
    "checkOut.at",
    "clockOut.at",
  ]);

  const inDate = toDateOrNull(inRaw);
  const outDate = toDateOrNull(outRaw);

  if (inDate && outDate) {
    const diff = Math.floor((outDate.getTime() - inDate.getTime()) / 60000);

    // Ignore impossible/too-long sessions for safety.
    if (diff > 0 && diff <= 24 * 60) return diff;
  }

  // Fallback HH:mm string.
  const byHHmm = minutesBetween(inRaw, outRaw, row.breakMinutes || 0);
  if (byHHmm > 0) return byHHmm;

  return 0;
}

function isAttendanceCompletedForPayroll(row) {
  if (!row || typeof row !== "object") return false;

  const outRaw = firstValueByPaths(row, [
    "checkOutAt",
    "checkedOutAt",
    "clockOutAt",
    "outAt",
    "endAt",
    "endTime",
    "checkOutTime",
    "clockOutTime",
    "timeOut",
    "checkOut.at",
    "clockOut.at",
  ]);

  if (outRaw) return true;

  const status = safeStr(
    row.status || row.attendanceStatus || row.state || row.lifecycleStatus
  ).toLowerCase();

  return [
    "completed",
    "complete",
    "checked_out",
    "checkout",
    "checkedout",
    "finished",
    "done",
    "closed",
    "success",
  ].includes(status);
}

function summarizeAttendanceItem(row, minutes) {
  const inRaw = firstValueByPaths(row, [
    "checkInAt",
    "checkedInAt",
    "clockInAt",
    "inAt",
    "startAt",
    "startTime",
    "checkInTime",
    "clockInTime",
    "timeIn",
    "checkIn.at",
    "clockIn.at",
  ]);

  const outRaw = firstValueByPaths(row, [
    "checkOutAt",
    "checkedOutAt",
    "clockOutAt",
    "outAt",
    "endAt",
    "endTime",
    "checkOutTime",
    "clockOutTime",
    "timeOut",
    "checkOut.at",
    "clockOut.at",
  ]);

  return {
    id: String(row?._id || ""),
    workDate: safeStr(row?.workDate || row?.date || row?.attendanceDate || ""),
    checkInAt: inRaw || null,
    checkOutAt: outRaw || null,
    minutes,
    hours: round2(minutes / 60),
    status: safeStr(row?.status || row?.attendanceStatus || row?.state),
  };
}

function normalizeComparableId(v) {
  if (v === undefined || v === null) return "";

  if (typeof v === "string" || typeof v === "number") {
    return safeStr(v);
  }

  if (typeof v === "object") {
    if (v instanceof Date) return "";

    if (v._id) return normalizeComparableId(v._id);
    if (v.id) return normalizeComparableId(v.id);

    // Mongo ObjectId / BSON ObjectId
    if (v._bsontype || v.constructor?.name === "ObjectId") {
      return safeStr(v.toString());
    }
  }

  return "";
}

function valueMatchesAnyPayrollId(value, idSet, seen = new WeakSet(), depth = 0) {
  if (value === undefined || value === null) return false;
  if (depth > 8) return false;

  const comparable = normalizeComparableId(value);
  if (comparable && idSet.has(comparable)) return true;

  if (Array.isArray(value)) {
    return value.some((x) =>
      valueMatchesAnyPayrollId(x, idSet, seen, depth + 1)
    );
  }

  if (typeof value === "object") {
    if (value instanceof Date) return false;

    if (seen.has(value)) return false;
    seen.add(value);

    for (const child of Object.values(value)) {
      if (valueMatchesAnyPayrollId(child, idSet, seen, depth + 1)) {
        return true;
      }
    }
  }

  return false;
}

function rowMatchesAnyPayrollIdentifier(row, personIds) {
  const idSet = new Set(
    uniqueNonEmptyStrings(personIds)
      .map(normalizeComparableId)
      .filter(Boolean)
  );

  if (!idSet.size || !row) return false;

  const directPaths = [
    "staffId",
    "employeeId",
    "userId",
    "principalId",
    "employeeUserId",
    "linkedUserId",
    "helperId",
    "workerId",
    "providerId",
    "assignedStaffId",
    "assignedUserId",
    "staffUserId",

    "assignmentId",
    "workAssignmentId",
    "shiftNeedId",
    "clinicShiftNeedId",
    "shiftId",
    "jobId",
    "needId",
    "bookingId",
    "contractId",

    "staff._id",
    "staff.id",
    "employee._id",
    "employee.id",
    "user._id",
    "user.id",
    "helper._id",
    "helper.id",
    "worker._id",
    "worker.id",
    "assignment._id",
    "assignment.id",
    "workAssignment._id",
    "workAssignment.id",
    "shiftNeed._id",
    "shiftNeed.id",
    "clinicShiftNeed._id",
    "clinicShiftNeed.id",
    "shift._id",
    "shift.id",
    "job._id",
    "job.id",
    "need._id",
    "need.id",
  ];

  for (const p of directPaths) {
    const v = getByPath(row, p);
    if (valueMatchesAnyPayrollId(v, idSet)) return true;
  }

  // ✅ Last safety net:
  // Some old Attendance rows have unknown nested shape.
  // We deep-match only against known payroll identifiers.
  return valueMatchesAnyPayrollId(row, idSet);
}

function mergeAttendanceRowsUnique(rows) {
  const out = [];
  const seen = new Set();

  for (const row of rows || []) {
    const key =
      safeStr(row?._id) ||
      [
        safeStr(row?.workDate || row?.date || row?.attendanceDate),
        safeStr(row?.checkInAt || row?.clockInAt || row?.startAt),
        safeStr(row?.checkOutAt || row?.clockOutAt || row?.endAt),
        safeStr(row?.staffId || row?.employeeId || row?.userId || row?.helperId),
      ].join("|");

    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(row);
  }

  return out;
}

function attendanceSortForPayroll() {
  return {
    workDate: 1,
    date: 1,
    attendanceDate: 1,
    checkInAt: 1,
    checkedInAt: 1,
    clockInAt: 1,
    inAt: 1,
    startAt: 1,
    createdAt: 1,
  };
}

function getAttendancePayableItems(rows) {
  let totalMinutes = 0;
  const payableItems = [];

  for (const row of rows || []) {
    const completed = isAttendanceCompletedForPayroll(row);
    const minutes = extractAttendanceWorkedMinutes(row);

    if (!completed || minutes <= 0) continue;

    totalMinutes += minutes;
    payableItems.push(summarizeAttendanceItem(row, minutes));
  }

  return { totalMinutes, payableItems };
}

async function getAttendanceRegularWorkSummaryForMonth({
  clinicId,
  monthKey,
  employeeId,
  employee,
  body,
}) {
  const cId = safeStr(clinicId);
  const mKey = safeStr(monthKey);
  const staffId = safeStr(employeeId);

  if (!Attendance) {
    return {
      minutes: 0,
      hours: 0,
      source: "attendance_model_missing",
      count: 0,
      payableCount: 0,
      items: [],
      personIds: [],
    };
  }

  if (!cId || !mKey || !staffId) {
    return {
      minutes: 0,
      hours: 0,
      source: "attendance_missing_query_keys",
      count: 0,
      payableCount: 0,
      items: [],
      personIds: [],
    };
  }

  const personIds = buildPayrollPersonIds({
    employeeId: staffId,
    employee,
    body,
  });

  const personOr = buildAttendancePersonOr(personIds);

  if (!personOr.length) {
    return {
      minutes: 0,
      hours: 0,
      source: "attendance_missing_person_ids",
      count: 0,
      payableCount: 0,
      items: [],
      personIds,
    };
  }

  const monthOr = buildAttendanceMonthOr(mKey);
  const clinicOr = buildAttendanceClinicOr(cId);

  const strictQuery = {
    $and: [{ $or: clinicOr }, { $or: personOr }, { $or: monthOr }],
  };

  let strictRows = [];
  let fallbackRows = [];
  let queryMode = "strict";

  try {
    strictRows = await Attendance.find(strictQuery)
      .setOptions({ strictQuery: false })
      .sort(attendanceSortForPayroll())
      .limit(2000)
      .lean();
  } catch (e) {
    console.log("[PAYROLL_PARTTIME_ATTENDANCE_WORK][STRICT_FAILED]", {
      clinicId: cId,
      employeeId: staffId,
      monthKey: mKey,
      error: e.message,
    });
    strictRows = [];
  }

  const strictPayable = getAttendancePayableItems(strictRows);

  // ✅ Production fallback:
  // If strict query cannot find payable rows, fetch clinic+month rows then
  // match identifiers in JS. This catches old/migrated schemas where fields
  // are nested or named as shiftNeedId / assignmentId / jobId.
  if (strictRows.length === 0 || strictPayable.totalMinutes <= 0) {
    queryMode = "fallback_clinic_month_deep_match";

    const fallbackQuery = {
      $and: [{ $or: clinicOr }, { $or: monthOr }],
    };

    try {
      const broadRows = await Attendance.find(fallbackQuery)
        .setOptions({ strictQuery: false })
        .sort(attendanceSortForPayroll())
        .limit(5000)
        .lean();

      fallbackRows = broadRows.filter((row) =>
        rowMatchesAnyPayrollIdentifier(row, personIds)
      );
    } catch (e) {
      console.log("[PAYROLL_PARTTIME_ATTENDANCE_WORK][FALLBACK_FAILED]", {
        clinicId: cId,
        employeeId: staffId,
        monthKey: mKey,
        error: e.message,
      });
      fallbackRows = [];
    }
  }

  const rows = mergeAttendanceRowsUnique([...strictRows, ...fallbackRows]);
  const { totalMinutes, payableItems } = getAttendancePayableItems(rows);

  const result = {
    minutes: totalMinutes,
    hours: round2(totalMinutes / 60),
    source:
      totalMinutes > 0
        ? `attendance.checkin_checkout.${queryMode}`
        : rows.length > 0
        ? `attendance.no_completed_payable_records.${queryMode}`
        : `attendance.no_records.${queryMode}`,
    count: rows.length,
    strictCount: strictRows.length,
    fallbackCount: fallbackRows.length,
    payableCount: payableItems.length,
    items: payableItems.slice(0, 31),
    personIds,
  };

  console.log("[PAYROLL_PARTTIME_ATTENDANCE_WORK]", {
    clinicId: cId,
    employeeId: staffId,
    monthKey: mKey,
    source: result.source,
    matchedRows: result.count,
    strictRows: result.strictCount,
    fallbackRows: result.fallbackCount,
    payableRows: result.payableCount,
    minutes: result.minutes,
    hours: result.hours,
    personIds,
  });

  return result;
}

function applyPartTimeOtExclusionToSalaryProfile({ salaryProfile, otSummary }) {
  const profile = salaryProfile || {};

  if (profile.employmentType !== "parttime") return profile;

  const hourlyRate = round2(clampMin0(profile.hourlyRate));
  const rw = profile.regularWork || {};

  const rawMinutes = Math.max(0, Math.floor(toNumber(rw.minutes)));
  const otMinutesExcluded = Math.min(
    rawMinutes,
    Math.max(0, Math.floor(toNumber(otSummary?.approvedMinutes)))
  );

  const payableMinutes = Math.max(0, rawMinutes - otMinutesExcluded);
  const payableHours = round2(payableMinutes / 60);

  if (rawMinutes <= 0 || hourlyRate <= 0) {
    return {
      ...profile,
      regularWork: {
        ...rw,
        rawMinutes,
        rawHours: round2(rawMinutes / 60),
        otMinutesExcluded,
        payableMinutes,
        payableHours,
      },
    };
  }

  return {
    ...profile,
    grossBase: round2(payableHours * hourlyRate),
    grossBaseSource: `${
      rw.source || "regularWork"
    }*staff_service.hourlyRate_minus_approved_ot_minutes`,
    regularWork: {
      ...rw,

      // Existing UI fields:
      minutes: payableMinutes,
      hours: payableHours,

      // Audit/debug fields:
      rawMinutes,
      rawHours: round2(rawMinutes / 60),
      otMinutesExcluded,
      payableMinutes,
      payableHours,
    },
  };
}

async function fetchEmployeeForPayroll(employeeId, authHeader) {
  let employee = null;
  let staffLookupError = "";

  try {
    employee = await getEmployeeByStaffId(employeeId, authHeader);
  } catch (e) {
    staffLookupError = e?.message || "staff lookup failed";
    console.log("⚠️ fetchEmployeeForPayroll failed:", staffLookupError);
  }

  return { employee, staffLookupError };
}

async function resolveSalaryBaseFromBackend({
  employee,
  body,
  clinicId,
  employeeId,
  month,
}) {
  const b = body || {};

  // ✅ Production fallback:
  // staff_service is still the source of truth when available.
  // But if staff_service is rate-limited / down / returns null,
  // payroll can still detect part-time from request body hints.
  const bodyHourlyRate = pickFirstPositiveNumber(b, [
    "hourlyRate",
    "hourlyWage",
    "wagePerHour",
    "ratePerHour",
  ]);

  const bodyMonthlySalary = pickFirstPositiveNumber(b, [
    "monthlySalary",
    "baseSalary",
    "salary",
    "monthlyWage",
    "grossBase",
    "grossMonthly",
  ]);

  const bodySaysPartTime =
    b.isPartTime === true ||
    b.isParttime === true ||
    b.partTime === true ||
    b.parttime === true ||
    normalizeEmploymentType(b.employmentType) === "parttime" ||
    normalizeEmploymentType(b.employeeType) === "parttime" ||
    normalizeEmploymentType(b.workType) === "parttime" ||
    bodyHourlyRate > 0;

  const bodySaysFullTime =
    b.isFullTime === true ||
    b.fullTime === true ||
    b.fulltime === true ||
    normalizeEmploymentType(b.employmentType) === "fulltime" ||
    normalizeEmploymentType(b.employeeType) === "fulltime" ||
    normalizeEmploymentType(b.workType) === "fulltime";

  const staffEmploymentRaw =
    employee?.employmentType || employee?.employeeType || employee?.workType;

  const staffEmploymentType = normalizeEmploymentType(staffEmploymentRaw);

  let employmentType = employee
    ? staffEmploymentType
    : bodySaysPartTime
    ? "parttime"
    : bodySaysFullTime
    ? "fulltime"
    : staffEmploymentType;

  // ✅ During migration / staff_service instability:
  // If Flutter clearly says this employee is part-time, do not let
  // missing/failed staff lookup silently become full-time.
  if (bodySaysPartTime) {
    employmentType = "parttime";
  }

  const monthlyFromStaff = resolveMonthlySalaryFromEmployee(employee);
  const hourlyFromStaff = resolvePartTimeHourlyFromEmployee(employee);

  const monthlyResolved =
    monthlyFromStaff > 0 ? monthlyFromStaff : bodyMonthlySalary;

  const hourlyResolved =
    hourlyFromStaff > 0 ? hourlyFromStaff : bodyHourlyRate;

  const monthlySalarySource =
    monthlyFromStaff > 0
      ? "staff_service.monthlySalary"
      : bodyMonthlySalary > 0
      ? "body.monthlySalary_fallback"
      : "missing";

  const hourlyRateSource =
    hourlyFromStaff > 0
      ? "staff_service.hourlyRate"
      : bodyHourlyRate > 0
      ? "body.hourlyRate_fallback"
      : "missing";

  const bodyRegularWork = extractRegularWorkSummary(b);

  let attendanceRegularWork = {
    minutes: 0,
    hours: 0,
    source: "not_used",
    count: 0,
    strictCount: 0,
    fallbackCount: 0,
    payableCount: 0,
    items: [],
    personIds: [],
  };

  if (employmentType === "parttime") {
    attendanceRegularWork = await getAttendanceRegularWorkSummaryForMonth({
      clinicId,
      monthKey: month,
      employeeId,
      employee,
      body: b,
    });
  }

  // ✅ Backend attendance wins for part-time.
  // Flutter/body regularWork remains fallback only.
  const regularWork =
    employmentType === "parttime" && attendanceRegularWork.minutes > 0
      ? attendanceRegularWork
      : bodyRegularWork;

  let grossBase = 0;
  let grossBaseSource = "missing";

  if (employmentType === "parttime") {
    if (regularWork.hours > 0 && hourlyResolved > 0) {
      grossBase = round2(regularWork.hours * hourlyResolved);
      grossBaseSource = `${regularWork.source}*${hourlyRateSource}`;
    } else if (monthlyResolved > 0) {
      // Compatibility fallback only.
      // Normal part-time payroll should use attendance hours * hourlyRate.
      grossBase = monthlyResolved;
      grossBaseSource = `${monthlySalarySource}_fallback_for_parttime`;
    } else if (clampMin0(b?.grossBase) > 0) {
      grossBase = round2(clampMin0(b.grossBase));
      grossBaseSource = "body.grossBase_fallback_migration";
    }
  } else {
    // ✅ Full-time flow unchanged.
    if (monthlyResolved > 0) {
      grossBase = monthlyResolved;
      grossBaseSource = monthlySalarySource;
    } else if (clampMin0(b?.grossBase) > 0) {
      grossBase = round2(clampMin0(b.grossBase));
      grossBaseSource = "body.grossBase_fallback_migration";
    }
  }

  return {
    employmentType,
    grossBase: round2(grossBase),
    grossBaseSource,

    hourlyRate: round2(hourlyResolved),
    hourlyRateSource,

    monthlySalaryFromStaff: round2(monthlyFromStaff),
    monthlySalaryResolved: round2(monthlyResolved),
    monthlySalarySource,

    regularWork,
    bodyRegularWork,
    attendanceRegularWork,
  };
}

function resolveLeaveDeductionBackendOnly({
  body,
  employee,
  oldDefaults,
  grossBase,
  employmentType,
}) {
  const absentDaysFromBody = pickFirstDefinedNumber(body, [
    "absentDays",
    "leaveAbsentDays",
    "leaveDays",
    "absenceDays",
    "unpaidLeaveDays",
  ]);

  const absentDaysFromEmployee = pickFirstDefinedNumber(employee, [
    "absentDays",
    "leaveAbsentDays",
    "leaveDays",
    "absenceDays",
    "unpaidLeaveDays",
  ]);

  const days =
    absentDaysFromBody !== null
      ? absentDaysFromBody
      : absentDaysFromEmployee !== null
      ? absentDaysFromEmployee
      : null;

  if (days !== null && days > 0 && employmentType === "fulltime") {
    return {
      amount: round2((clampMin0(grossBase) / 30) * clampMin0(days)),
      source:
        absentDaysFromBody !== null
          ? "body.absentDays*grossBase/30"
          : "staff_service.absentDays*grossBase/30",
      absentDays: round2(days),
    };
  }

  const amount = resolveMoneyInput({
    body,
    employee,
    oldDefaults,
    bodyKeys: [
      "otherDeduction",
      "leaveDeduction",
      "absentDeduction",
      "deduction",
    ],
    employeeKeys: [
      "otherDeduction",
      "leaveDeduction",
      "absentDeduction",
      "deduction",
      "monthlyDeduction",
    ],
    oldKeys: ["otherDeduction", "leaveDeduction", "absentDeduction"],
    defaultValue: 0,
  });

  return {
    amount,
    source: amount > 0 ? "deduction_amount" : "none",
    absentDays: days !== null ? round2(days) : 0,
  };
}

function resolveOtBaseHourlyFromProfile({
  employmentType,
  grossBase,
  hourlyRate,
}) {
  if (employmentType === "parttime") {
    return {
      otBaseHourly: round2(clampMin0(hourlyRate)),
      source:
        hourlyRate > 0 ? "staff_service.hourlyRate" : "missing_parttime_hourly",
    };
  }

  const otBaseHourly = computeFullTimeOtBaseHourly(grossBase);
  return {
    otBaseHourly,
    source: otBaseHourly > 0 ? "grossBase/30/8" : "missing_fulltime_grossBase",
  };
}

// ================= TAX / SSO =================
const DEFAULT_SSO_EMPLOYEE_RATE = 0.05;
const DEFAULT_SSO_MAX_WAGE_BASE = 17500;

function normalizeTaxMode(v) {
  const s = safeStr(v).toUpperCase();
  if (s === "NO_WITHHOLDING") return "NO_WITHHOLDING";
  if (s === "NONE") return "NO_WITHHOLDING";
  if (s === "NO_TAX") return "NO_WITHHOLDING";
  return "WITHHOLDING";
}

function normalizeGrossBaseMode(v) {
  const s = safeStr(v).toUpperCase();
  if (s === "POST_DEDUCTION") return "POST_DEDUCTION";
  if (s === "AUTO") return "AUTO";
  return "PRE_DEDUCTION";
}

function resolveClinicSsoConfig(clinicRow) {
  const enabled = clinicRow?.socialSecurity?.enabled !== false;

  const employeeRateRaw = toNumber(clinicRow?.socialSecurity?.employeeRate);
  const maxWageBaseRaw = toNumber(clinicRow?.socialSecurity?.maxWageBase);

  const employeeRate =
    employeeRateRaw > 0 ? employeeRateRaw : DEFAULT_SSO_EMPLOYEE_RATE;

  const maxWageBase =
    maxWageBaseRaw > 0 ? maxWageBaseRaw : DEFAULT_SSO_MAX_WAGE_BASE;

  const maxEmployeeMonthly = round2(maxWageBase * employeeRate);

  return {
    enabled,
    employeeRate,
    maxWageBase,
    maxEmployeeMonthly,
  };
}

function normalizeSsoEmployeeMonthly(v, maxEmployeeMonthly) {
  return round2(clamp(clampMin0(v), 0, clampMin0(maxEmployeeMonthly)));
}

function computeSsoEmployeeMonthlyFromClinicConfig(salaryBaseForSso, ssoConfig) {
  if (!ssoConfig?.enabled) return 0;

  const contributableBase = Math.min(
    clampMin0(salaryBaseForSso),
    clampMin0(ssoConfig.maxWageBase)
  );

  return round2(contributableBase * clampMin0(ssoConfig.employeeRate));
}

// ================= AUTH PICKER =================
function pickAuth(req) {
  const u = req.user || {};
  const uc = req.userCtx || {};

  const role = safeStr(u.role || u.activeRole || uc.role || uc.activeRole);
  const clinicId = safeStr(u.clinicId || uc.clinicId);
  const userId = safeStr(
    u.userId || u.id || u._id || uc.userId || uc.id || uc._id
  );
  const staffId = safeStr(
    u.staffId || u.employeeId || uc.staffId || uc.employeeId
  );

  return { role, clinicId, userId, staffId };
}

function assertAdminContext(req) {
  const { clinicId, userId, role } = pickAuth(req);

  if (!clinicId) throwHttp(401, "Missing clinicId in token");
  if (!userId) throwHttp(401, "Missing userId in token");
  if (!isAdminRole(role)) throwHttp(403, "Forbidden (admin only)");

  return { clinicId, userId, role };
}

// ================= ACCESS GUARD =================
function guardPayslipAccess(req, res, next) {
  const { role, staffId: staffIdInToken } = pickAuth(req);
  const employeeId = safeStr(req.params.employeeId || req.body?.employeeId);

  if (!role) return res.status(401).json({ message: "Unauthorized" });

  if (isAdminRole(role)) return next();

  if (role === "employee" || role === "staff") {
    if (!employeeId || !staffIdInToken) {
      return res.status(400).json({ message: "Missing employeeId/staffId" });
    }

    if (employeeId !== staffIdInToken) {
      return res.status(403).json({ message: "Forbidden" });
    }

    return next();
  }

  return res.status(403).json({ message: "Forbidden" });
}

// ================= OT helpers =================
function getOtMinutesForPayroll(row) {
  const rawApproved = row?.approvedMinutes;
  const rawMinutes = row?.minutes;

  const mins = Math.max(
    0,
    Math.floor(
      Number(
        rawApproved !== undefined && rawApproved !== null
          ? rawApproved
          : rawMinutes || 0
      )
    )
  );

  return Number.isFinite(mins) ? mins : 0;
}

function getOtMultiplierForPayroll(row) {
  const mul = Number(row?.multiplier);
  return Number.isFinite(mul) && mul > 0 ? mul : 1.5;
}

async function getApprovedOtSummaryForMonth({ clinicId, monthKey, employeeId }) {
  const cId = safeStr(clinicId);
  const mKey = safeStr(monthKey);
  const staffId = safeStr(employeeId);

  if (!cId || !mKey || !staffId) {
    return {
      monthKey: mKey,
      approvedMinutes: 0,
      approvedWeightedHours: 0,
      records: [],
      count: 0,
      bySource: {},
    };
  }

  const q = {
    clinicId: cId,
    monthKey: mKey,
    status: { $in: PAYROLL_OT_STATUSES },
    $and: [
      {
        $or: [{ staffId }, { principalId: staffId }],
      },
      {
        $or: [
          { source: { $in: PAYROLL_OT_SOURCES } },
          { source: { $exists: false } },
          { source: "" },
          { source: null },
        ],
      },
    ],
  };

  const rows = await Overtime.find(q)
    .select({
      workDate: 1,
      monthKey: 1,
      minutes: 1,
      approvedMinutes: 1,
      multiplier: 1,
      status: 1,
      source: 1,
      note: 1,
      userId: 1,
      principalId: 1,
      staffId: 1,
      attendanceSessionId: 1,
      lockedBy: 1,
      lockedAt: 1,
      lockedMonth: 1,
      createdAt: 1,
      updatedAt: 1,
    })
    .sort({ workDate: 1, createdAt: 1 })
    .lean();

  let approvedMinutes = 0;
  let approvedWeightedHours = 0;
  const bySource = {};

  for (const row of rows) {
    const mins = getOtMinutesForPayroll(row);
    const multiplier = getOtMultiplierForPayroll(row);
    const weightedHours = (mins / 60) * multiplier;

    approvedMinutes += mins;
    approvedWeightedHours += weightedHours;

    const sourceKey = safeStr(row.source) || "attendance_legacy";

    if (!bySource[sourceKey]) {
      bySource[sourceKey] = {
        count: 0,
        approvedMinutes: 0,
        approvedWeightedHours: 0,
      };
    }

    bySource[sourceKey].count += 1;
    bySource[sourceKey].approvedMinutes += mins;
    bySource[sourceKey].approvedWeightedHours = round2(
      bySource[sourceKey].approvedWeightedHours + weightedHours
    );
  }

  const summary = {
    monthKey: mKey,
    approvedMinutes,
    approvedWeightedHours: round2(approvedWeightedHours),
    count: rows.length,
    records: rows,
    bySource,
  };

  console.log("[PAYROLL_OT_SUMMARY]", {
    clinicId: cId,
    employeeId: staffId,
    monthKey: mKey,
    count: summary.count,
    approvedMinutes: summary.approvedMinutes,
    approvedWeightedHours: summary.approvedWeightedHours,
    bySource: summary.bySource,
  });

  return summary;
}

async function lockOtRowsForPayrollClose({ c, payrollClose }) {
  const records = Array.isArray(c?.otSummary?.records)
    ? c.otSummary.records
    : [];

  const ids = records.map((x) => x?._id).filter(Boolean);

  if (!ids.length) {
    return {
      ok: true,
      matched: 0,
      modified: 0,
      reason: "no_ot_records",
      payrollCloseId: String(payrollClose?._id || ""),
    };
  }

  try {
    const r = await Overtime.updateMany(
      {
        _id: { $in: ids },
        clinicId: c.clinicId,
        monthKey: c.month,
        status: { $in: PAYROLL_OT_STATUSES },
      },
      {
        $set: {
          status: "locked",
          lockedBy: c.adminUserId,
          lockedAt: new Date(),
          lockedMonth: c.month,
        },
      }
    );

    const result = {
      ok: true,
      matched: r.matchedCount ?? r.n ?? 0,
      modified: r.modifiedCount ?? r.nModified ?? 0,
      payrollCloseId: String(payrollClose?._id || ""),
    };

    console.log("[PAYROLL_OT_LOCK]", {
      clinicId: c.clinicId,
      employeeId: c.employeeId,
      month: c.month,
      ...result,
    });

    return result;
  } catch (e) {
    const result = {
      ok: false,
      matched: 0,
      modified: 0,
      error: e.message,
      payrollCloseId: String(payrollClose?._id || ""),
    };

    console.error("[PAYROLL_OT_LOCK][FAILED]", {
      clinicId: c.clinicId,
      employeeId: c.employeeId,
      month: c.month,
      ...result,
    });

    return result;
  }
}

// ================= EMPLOYEE userId resolver =================
async function resolveEmployeeUserId({
  clinicId,
  monthKey,
  staffId,
  bodyEmployeeUserId,
  adminUserId,
  token,
  employee,
}) {
  const fromBody = safeStr(bodyEmployeeUserId);
  if (fromBody) {
    return { employeeUserId: fromBody, source: "body" };
  }

  const fromEmployee = safeStr(
    employee?.userId || employee?.linkedUserId || employee?.linked_user_id
  );
  if (fromEmployee) {
    return { employeeUserId: fromEmployee, source: "staff_service" };
  }

  try {
    const emp = await getEmployeeByStaffId(staffId, token);
    const u = safeStr(emp?.userId || emp?.linkedUserId || emp?.linked_user_id);
    if (u) return { employeeUserId: u, source: "staff_service_lookup" };
  } catch (e) {
    console.log("⚠️ staff_service userId lookup failed:", e.message);
  }

  const row = await Overtime.findOne({
    clinicId: safeStr(clinicId),
    monthKey: safeStr(monthKey),
    staffId: safeStr(staffId),
    userId: { $nin: ["", null] },
  })
    .select({ userId: 1 })
    .sort({ createdAt: -1 })
    .lean();

  const inferred = safeStr(row?.userId);
  if (inferred) {
    return { employeeUserId: inferred, source: "overtime" };
  }

  const fallback = safeStr(adminUserId);
  return { employeeUserId: fallback, source: "admin_fallback" };
}

// ================= auth internal call =================
async function calcWithheldByYTDFromAuth({
  userId,
  taxYear,
  incomeYTD,
  ssoYTD,
  pvdYTD,
  taxPaidYTD,
}) {
  const base = baseUrlNoSlash(process.env.AUTH_USER_SERVICE_URL);
  if (!base) throw new Error("Missing AUTH_USER_SERVICE_URL");

  const internalKey = safeStr(process.env.INTERNAL_SERVICE_KEY);
  if (!internalKey) throw new Error("Missing INTERNAL_SERVICE_KEY");

  if (!userId) throw new Error("Missing userId for AUTH_INTERNAL");

  const body = {
    userId,
    employeeId: userId,
    incomeYTD,
    ssoYTD,
    pvdYTD,
    taxPaidYTD,
  };

  const candidates = [
    `${base}/internal/payroll/calc-tax-ytd?year=${taxYear}`,
    `${base}/api/internal/payroll/calc-tax-ytd?year=${taxYear}`,
    `${base}/users/internal/payroll/calc-tax-ytd?year=${taxYear}`,
    `${base}/api/users/internal/payroll/calc-tax-ytd?year=${taxYear}`,
  ];

  const headers = {
    "Content-Type": "application/json",
    "x-internal-key": internalKey,
  };

  let lastErr = null;

  for (const url of candidates) {
    try {
      const res = await postJson(url, body, headers);
      if (res.status === 200) return res.data;

      lastErr = new Error(
        `AUTH_INTERNAL not 200: ${res.status} ${JSON.stringify(res.data)}`
      );
    } catch (e) {
      lastErr = e;
    }
  }

  throw lastErr || new Error("AUTH_INTERNAL call failed");
}

// ================= DISPLAY SNAPSHOT =================
function buildDisplaySnapshot({
  salaryBaseForSso,
  salaryBaseAfterLeave,
  leaveDeduction,
  otSummary,
  otPayFinal,
  bonusFinal,
  otherAllowanceFinal,
  withheldTaxMonthly,
  ssoM,
  pvdM,
  netPay,
}) {
  const displayNetBeforeOt = round2(clampMin0(salaryBaseAfterLeave));
  const displayLeaveDeduction = round2(clampMin0(leaveDeduction));
  const displayOtHours = round2(clampMin0(otSummary?.approvedWeightedHours));
  const displayOtAmount = round2(clampMin0(otPayFinal));
  const displayGrossBeforeTax = round2(
    Math.max(
      0,
      clampMin0(salaryBaseAfterLeave) +
        clampMin0(otPayFinal) +
        clampMin0(bonusFinal) +
        clampMin0(otherAllowanceFinal)
    )
  );
  const displayTaxAmount = round2(clampMin0(withheldTaxMonthly));
  const displaySsoAmount = round2(clampMin0(ssoM));
  const displayNetPay = round2(clampMin0(netPay));

  return {
    displayNetBeforeOt,
    displayLeaveDeduction,
    displayOtHours,
    displayOtAmount,
    displayGrossBeforeTax,
    displayTaxAmount,
    displaySsoAmount,
    displayNetPay,
    displayPvdAmount: round2(clampMin0(pvdM)),
    displaySalaryBaseForSso: round2(clampMin0(salaryBaseForSso)),
  };
}

// ================= PAYSLIP SUMMARY =================
function buildPayslipSummary(row) {
  const salary = round2(clampMin0(row?.grossBase));
  const socialSecurity = round2(clampMin0(row?.ssoEmployeeMonthly));
  const ot = round2(clampMin0(row?.otPay));
  const commission = round2(clampMin0(row?.otherAllowance));
  const bonus = round2(clampMin0(row?.bonus));
  const leaveDeduction = round2(clampMin0(row?.otherDeduction));
  const tax = round2(clampMin0(row?.withheldTaxMonthly));
  const pvd = round2(clampMin0(row?.pvdEmployeeMonthly));
  const netPay = round2(clampMin0(row?.netPay));

  return {
    employeeId: safeStr(row?.employeeId),
    clinicId: safeStr(row?.clinicId),
    month: safeStr(row?.month),
    amounts: {
      salary,
      socialSecurity,
      ot,
      commission,
      bonus,
      leaveDeduction,
      tax,
      pvd,
      netPay,
      grossBeforeTax: round2(
        clampMin0(row?.displayGrossBeforeTax || row?.grossMonthly)
      ),
    },
    meta: {
      source: "backend_final",
      isClosedPayroll: true,
      grossBaseModeApplied: safeStr(row?.snapshot?.grossBaseModeApplied),
      payrollCalculator: safeStr(
        row?.snapshot?.payrollCalculator || "backend_only"
      ),
    },
  };
}

function buildPayslipSummaryFromComputed(c) {
  return {
    employeeId: c.employeeId,
    clinicId: c.clinicId,
    month: c.month,
    amounts: {
      salary: c.grossBaseFinal,
      socialSecurity: c.ssoM,
      ot: c.otPayFinal,
      commission: c.otherAllowanceFinal,
      bonus: c.bonusFinal,
      leaveDeduction: c.leaveDeduction,
      tax: c.withheldTaxMonthly,
      pvd: c.pvdM,
      netPay: c.netPay,
      grossBeforeTax: c.display.displayGrossBeforeTax,
    },
    meta: {
      source: "backend_preview",
      isClosedPayroll: false,
      grossBaseModeApplied: c.payrollResolved.appliedMode,
      payrollCalculator: "backend_only",
    },
  };
}

// ================= PAYROLL COMPUTATION CORE =================
function resolvePayrollComputationBackendOnly({
  grossBase,
  otPay,
  bonus,
  otherAllowance,
  otherDeduction,
  grossBaseMode,
}) {
  const requestedMode = normalizeGrossBaseMode(grossBaseMode);

  const salaryBasePreDeduction = round2(clampMin0(grossBase));
  const leaveDeduction = round2(clampMin0(otherDeduction));
  const otPayFinal = round2(clampMin0(otPay));
  const bonusFinal = round2(clampMin0(bonus));
  const allowanceFinal = round2(clampMin0(otherAllowance));

  const buildPre = () => ({
    appliedMode: "PRE_DEDUCTION",
    expectedGrossBeforeTax: 0,
    salaryBaseForSso: salaryBasePreDeduction,
    salaryBaseAfterLeave: round2(
      Math.max(0, salaryBasePreDeduction - leaveDeduction)
    ),
    leaveDeduction,
    otPay: otPayFinal,
    bonus: bonusFinal,
    otherAllowance: allowanceFinal,
    netBeforeTaxAndPvd: round2(
      Math.max(
        0,
        salaryBasePreDeduction -
          leaveDeduction +
          otPayFinal +
          bonusFinal +
          allowanceFinal
      )
    ),
    preDeductionNetBeforeTax: round2(
      Math.max(
        0,
        salaryBasePreDeduction -
          leaveDeduction +
          otPayFinal +
          bonusFinal +
          allowanceFinal
      )
    ),
    postDeductionNetBeforeTax: round2(
      Math.max(
        0,
        salaryBasePreDeduction + otPayFinal + bonusFinal + allowanceFinal
      )
    ),
  });

  const buildPost = () => ({
    appliedMode: "POST_DEDUCTION",
    expectedGrossBeforeTax: 0,
    salaryBaseForSso: round2(salaryBasePreDeduction + leaveDeduction),
    salaryBaseAfterLeave: salaryBasePreDeduction,
    leaveDeduction,
    otPay: otPayFinal,
    bonus: bonusFinal,
    otherAllowance: allowanceFinal,
    netBeforeTaxAndPvd: round2(
      Math.max(
        0,
        salaryBasePreDeduction + otPayFinal + bonusFinal + allowanceFinal
      )
    ),
    preDeductionNetBeforeTax: round2(
      Math.max(
        0,
        salaryBasePreDeduction -
          leaveDeduction +
          otPayFinal +
          bonusFinal +
          allowanceFinal
      )
    ),
    postDeductionNetBeforeTax: round2(
      Math.max(
        0,
        salaryBasePreDeduction + otPayFinal + bonusFinal + allowanceFinal
      )
    ),
  });

  if (requestedMode === "POST_DEDUCTION") return buildPost();

  return buildPre();
}

async function computePayrollForMonth({
  req,
  clinicId,
  employeeId,
  month,
  body,
  existingYtdOverride = null,
}) {
  const b = body || {};
  const oldDefaults =
    b.__oldPayrollDefaults && typeof b.__oldPayrollDefaults === "object"
      ? b.__oldPayrollDefaults
      : {};

  const taxMode = normalizeTaxMode(b.taxMode || oldDefaults.taxMode);
  const grossBaseMode = normalizeGrossBaseMode(
    b.grossBaseMode || oldDefaults.grossBaseMode
  );
  const taxYear = monthToTaxYear(month);

  const { clinicId: clinicIdFromToken, userId: adminUserId } =
    assertAdminContext(req);

  if (safeStr(clinicId) !== clinicIdFromToken) {
    throwHttp(403, "Forbidden (clinic mismatch)");
  }

  const clinicRow = await Clinic.findOne({ clinicId: clinicIdFromToken }).lean();
  const ssoConfig = resolveClinicSsoConfig(clinicRow);

  const { employee, staffLookupError } = await fetchEmployeeForPayroll(
    employeeId,
    req.headers.authorization
  );

  const otSummary = await getApprovedOtSummaryForMonth({
    clinicId: clinicIdFromToken,
    monthKey: month,
    employeeId,
  });

  let salaryProfile = await resolveSalaryBaseFromBackend({
    employee,
    body: b,
    clinicId: clinicIdFromToken,
    employeeId,
    month,
  });

  // ✅ Part-time only:
  // normal wage = attendance worked minutes - approved OT minutes
  // OT pay is paid separately by weighted OT hours.
  // ✅ Full-time is returned unchanged by this helper.
  salaryProfile = applyPartTimeOtExclusionToSalaryProfile({
    salaryProfile,
    otSummary,
  });

  const grossBaseFinal = round2(clampMin0(salaryProfile.grossBase));

  const bonusFinal = resolveMoneyInput({
    body: b,
    employee,
    oldDefaults,
    bodyKeys: ["bonus"],
    employeeKeys: [
      "bonus",
      "monthlyBonus",
      "defaultBonus",
      "commission",
      "monthlyCommission",
    ],
    oldKeys: ["bonus"],
    defaultValue: 0,
  });

  const otherAllowanceFinal = resolveMoneyInput({
    body: b,
    employee,
    oldDefaults,
    bodyKeys: ["otherAllowance", "allowance", "commissionAllowance"],
    employeeKeys: [
      "otherAllowance",
      "allowance",
      "monthlyAllowance",
      "commissionAllowance",
    ],
    oldKeys: ["otherAllowance"],
    defaultValue: 0,
  });

  const leaveDeductionResolved = resolveLeaveDeductionBackendOnly({
    body: b,
    employee,
    oldDefaults,
    grossBase: grossBaseFinal,
    employmentType: salaryProfile.employmentType,
  });

  const otherDeductionFinal = round2(clampMin0(leaveDeductionResolved.amount));

  const pvdM = resolveMoneyInput({
    body: b,
    employee,
    oldDefaults,
    bodyKeys: ["pvdEmployeeMonthly"],
    employeeKeys: ["pvdEmployeeMonthly", "pvd", "providentFund"],
    oldKeys: ["pvdEmployeeMonthly"],
    defaultValue: 0,
  });

  const otRateResolved = resolveOtBaseHourlyFromProfile({
    employmentType: salaryProfile.employmentType,
    grossBase: grossBaseFinal,
    hourlyRate: salaryProfile.hourlyRate,
  });

  const calculatedOtPay =
    otRateResolved.otBaseHourly > 0
      ? round2(otSummary.approvedWeightedHours * otRateResolved.otBaseHourly)
      : 0;

  const allowManualOtPayOverride = b.allowManualOtPayOverride === true;
  const otPayFromClient = round2(clampMin0(b.otPay));
  const otPayFinal =
    allowManualOtPayOverride && otPayFromClient > 0
      ? otPayFromClient
      : calculatedOtPay;

  const payrollResolved = resolvePayrollComputationBackendOnly({
    grossBase: grossBaseFinal,
    otPay: otPayFinal,
    bonus: bonusFinal,
    otherAllowance: otherAllowanceFinal,
    otherDeduction: otherDeductionFinal,
    grossBaseMode,
  });

  const salaryBaseForSso = round2(payrollResolved.salaryBaseForSso);
  const salaryBaseAfterLeave = round2(payrollResolved.salaryBaseAfterLeave);
  const leaveDeduction = round2(payrollResolved.leaveDeduction);

  const ssoM = computeSsoEmployeeMonthlyFromClinicConfig(
    salaryBaseForSso,
    ssoConfig
  );

  const netBeforeTaxAndPvd = round2(
    Math.max(
      0,
      salaryBaseForSso -
        ssoM -
        leaveDeduction +
        otPayFinal +
        bonusFinal +
        otherAllowanceFinal
    )
  );

  let ytd = existingYtdOverride;
  if (!ytd) {
    ytd = await TaxYTD.findOne({ employeeId, taxYear }).lean();
  }

  const ytdBefore = {
    incomeYTD: round2(clampMin0(ytd?.incomeYTD)),
    ssoYTD: round2(clampMin0(ytd?.ssoYTD)),
    pvdYTD: round2(clampMin0(ytd?.pvdYTD)),
    taxPaidYTD: round2(clampMin0(ytd?.taxPaidYTD)),
  };

  const incomeYTD_after = round2(ytdBefore.incomeYTD + netBeforeTaxAndPvd);
  const ssoYTD_after = round2(ytdBefore.ssoYTD + ssoM);
  const pvdYTD_after = round2(ytdBefore.pvdYTD + pvdM);

  let resolved = null;
  let taxCalc = null;
  let withheldTaxMonthly = 0;
  let warning = null;

  if (taxMode === "WITHHOLDING") {
    resolved = await resolveEmployeeUserId({
      clinicId: clinicIdFromToken,
      monthKey: month,
      staffId: employeeId,
      bodyEmployeeUserId: safeStr(b.employeeUserId),
      adminUserId,
      token: req.headers.authorization,
      employee,
    });

    taxCalc = await calcWithheldByYTDFromAuth({
      userId: resolved.employeeUserId,
      taxYear,
      incomeYTD: incomeYTD_after,
      ssoYTD: ssoYTD_after,
      pvdYTD: pvdYTD_after,
      taxPaidYTD: ytdBefore.taxPaidYTD,
    });

    withheldTaxMonthly = round2(clampMin0(taxCalc?.withheldThisMonth));

    warning =
      resolved.source === "admin_fallback"
        ? "employeeUserId not found (body/staff_service/overtime). Tax calc fell back to admin userId. Please send employeeUserId from client for accuracy."
        : null;
  } else {
    withheldTaxMonthly = 0;
    taxCalc = {
      taxMode: "NO_WITHHOLDING",
      withheldThisMonth: 0,
      note: "Skipped tax withholding by taxMode=NO_WITHHOLDING",
    };
  }

  const netPay = round2(
    Math.max(0, netBeforeTaxAndPvd - withheldTaxMonthly - pvdM)
  );
  const grossMonthly = netBeforeTaxAndPvd;

  const display = buildDisplaySnapshot({
    salaryBaseForSso,
    salaryBaseAfterLeave,
    leaveDeduction,
    otSummary,
    otPayFinal,
    bonusFinal,
    otherAllowanceFinal,
    withheldTaxMonthly,
    ssoM,
    pvdM,
    netPay,
  });

  const ignoredClientInputs = {
    grossBaseInput: round2(clampMin0(b.grossBase)),
    otPayInput: round2(clampMin0(b.otPay)),
    ssoEmployeeMonthlyInput: normalizeSsoEmployeeMonthly(
      b.ssoEmployeeMonthly,
      ssoConfig.maxEmployeeMonthly
    ),
    grossMonthlyInput: round2(clampMin0(b.grossMonthly)),
    netPayInput: round2(clampMin0(b.netPay)),
    withheldTaxMonthlyInput: round2(clampMin0(b.withheldTaxMonthly)),
  };

  console.log("[PAYROLL_COMPUTE][BACKEND_ONLY]", {
    clinicId: clinicIdFromToken,
    employeeId,
    month,
    employmentType: salaryProfile.employmentType,
    grossBaseFinal,
    grossBaseSource: salaryProfile.grossBaseSource,
    hourlyRate: salaryProfile.hourlyRate,
    regularWork: salaryProfile.regularWork,
    attendanceRegularWork: salaryProfile.attendanceRegularWork,
    bodyRegularWork: salaryProfile.bodyRegularWork,
    staffLookupError,
    bonusFinal,
    otherAllowanceFinal,
    otherDeductionFinal,
    leaveDeductionResolved,
    pvdM,
    approvedMinutes: otSummary.approvedMinutes,
    approvedWeightedHours: otSummary.approvedWeightedHours,
    otBySource: otSummary.bySource,
    otBaseHourly: otRateResolved.otBaseHourly,
    otBaseHourlySource: otRateResolved.source,
    calculatedOtPay,
    allowManualOtPayOverride,
    otPayFinal,
    ignoredClientInputs,
  });

  return {
    clinicId: clinicIdFromToken,
    employeeId,
    month,
    taxYear,
    adminUserId,

    employee,
    staffLookupError,
    salaryProfile,
    leaveDeductionResolved,
    ssoConfig,
    otSummary,
    otRateResolved,
    payrollResolved,
    display,

    grossBaseMode,
    grossBaseFinal,
    bonusFinal,
    otherAllowanceFinal,
    otherDeductionFinal,
    salaryBaseForSso,
    salaryBaseAfterLeave,
    leaveDeduction,
    otPayFinal,
    calculatedOtPay,
    ssoM,
    pvdM,
    netBeforeTaxAndPvd,
    grossMonthly,
    withheldTaxMonthly,
    netPay,
    taxMode,
    taxCalc,
    resolved,
    warning,
    ytdBefore,
    incomeYTD_after,
    ssoYTD_after,
    pvdYTD_after,
    ignoredClientInputs,
  };
}

function buildPayrollClosePayload(c) {
  const otRecordIds = Array.isArray(c.otSummary?.records)
    ? c.otSummary.records.map((x) => String(x?._id || "")).filter(Boolean)
    : [];

  return {
    clinicId: c.clinicId,
    employeeId: c.employeeId,
    month: c.month,

    grossMonthly: c.grossMonthly,
    withheldTaxMonthly: c.withheldTaxMonthly,
    netPay: c.netPay,

    grossBase: c.grossBaseFinal,
    otPay: c.otPayFinal,
    bonus: c.bonusFinal,
    otherAllowance: c.otherAllowanceFinal,
    otherDeduction: c.otherDeductionFinal,

    ssoEmployeeMonthly: c.ssoM,
    pvdEmployeeMonthly: c.pvdM,

    otApprovedMinutes: Math.max(
      0,
      Math.floor(Number(c.otSummary.approvedMinutes || 0))
    ),
    otApprovedWeightedHours: round2(
      clampMin0(c.otSummary.approvedWeightedHours)
    ),
    otApprovedCount: Math.max(0, Math.floor(Number(c.otSummary.count || 0))),

    displayNetBeforeOt: c.display.displayNetBeforeOt,
    displayLeaveDeduction: c.display.displayLeaveDeduction,
    displayOtHours: c.display.displayOtHours,
    displayOtAmount: c.display.displayOtAmount,
    displayGrossBeforeTax: c.display.displayGrossBeforeTax,
    displayTaxAmount: c.display.displayTaxAmount,
    displaySsoAmount: c.display.displaySsoAmount,
    displayNetPay: c.display.displayNetPay,

    locked: true,
    closedBy: c.adminUserId,
    taxMode: c.taxMode,

    snapshot: {
      payrollCalculator: "backend_only",
      taxYear: c.taxYear,
      allowanceTotalAnnual: 0,
      incomeYTD_after: c.incomeYTD_after,
      ssoYTD_after: c.ssoYTD_after,
      pvdYTD_after: c.pvdYTD_after,
      taxableYTD: round2(clampMin0(c.taxCalc?.taxableYTD)),
      taxDueYTD: round2(clampMin0(c.taxCalc?.taxDueYTD)),
      taxPaidYTD_before: c.ytdBefore.taxPaidYTD,
      taxPaidYTD_after:
        c.taxMode === "WITHHOLDING"
          ? round2(c.ytdBefore.taxPaidYTD + c.withheldTaxMonthly)
          : round2(c.ytdBefore.taxPaidYTD),

      grossBaseModeRequested: normalizeGrossBaseMode(c.grossBaseMode),
      grossBaseModeApplied: c.payrollResolved.appliedMode,
      expectedGrossBeforeTax: 0,
      preDeductionNetBeforeTax: c.payrollResolved.preDeductionNetBeforeTax,
      postDeductionNetBeforeTax: c.payrollResolved.postDeductionNetBeforeTax,

      grossBaseSource: c.salaryProfile.grossBaseSource,
      employmentTypeResolved: c.salaryProfile.employmentType,
      hourlyRateResolved: c.salaryProfile.hourlyRate,
      monthlySalaryFromStaff: c.salaryProfile.monthlySalaryFromStaff,

      regularWorkMinutes: c.salaryProfile.regularWork.minutes,
      regularWorkHours: c.salaryProfile.regularWork.hours,
      regularWorkSource: c.salaryProfile.regularWork.source,

      regularWorkRawMinutes:
        c.salaryProfile.regularWork.rawMinutes ??
        c.salaryProfile.regularWork.minutes,
      regularWorkRawHours:
        c.salaryProfile.regularWork.rawHours ??
        c.salaryProfile.regularWork.hours,
      regularWorkPayableMinutes:
        c.salaryProfile.regularWork.payableMinutes ??
        c.salaryProfile.regularWork.minutes,
      regularWorkPayableHours:
        c.salaryProfile.regularWork.payableHours ??
        c.salaryProfile.regularWork.hours,
      regularWorkOtMinutesExcluded:
        c.salaryProfile.regularWork.otMinutesExcluded ?? 0,

      attendanceRegularWork: c.salaryProfile.attendanceRegularWork || null,
      bodyRegularWork: c.salaryProfile.bodyRegularWork || null,

      ssoBaseUsed: c.salaryBaseForSso,
      salaryBaseAfterLeave: c.salaryBaseAfterLeave,
      leaveDeduction: c.leaveDeduction,
      leaveDeductionSource: c.leaveDeductionResolved?.source || "none",
      absentDaysUsed: c.leaveDeductionResolved?.absentDays || 0,

      otPayUsed: c.otPayFinal,
      calculatedOtPay: c.calculatedOtPay,
      otBaseHourlyResolved: c.otRateResolved.otBaseHourly,
      otBaseHourlySource: c.otRateResolved.source,
      otApprovedMinutes: c.otSummary.approvedMinutes,
      otApprovedWeightedHours: c.otSummary.approvedWeightedHours,
      otApprovedCount: c.otSummary.count,
      otBreakdownBySource: c.otSummary.bySource || {},
      otRecordIds,

      staffLookupError: c.staffLookupError || "",
      bonusUsed: c.bonusFinal,
      otherAllowanceUsed: c.otherAllowanceFinal,
      pvdEmployeeMonthlyApplied: c.pvdM,
      netBeforeTaxAndPvd: c.netBeforeTaxAndPvd,

      ssoEnabled: c.ssoConfig.enabled,
      ssoRate: c.ssoConfig.employeeRate,
      ssoMaxWageBase: c.ssoConfig.maxWageBase,
      ssoMaxEmployeeMonthly: c.ssoConfig.maxEmployeeMonthly,
      ssoEmployeeMonthlyInput: c.ignoredClientInputs.ssoEmployeeMonthlyInput,
      ssoEmployeeMonthlyApplied: c.ssoM,

      ignoredClientInputs: c.ignoredClientInputs,
    },
  };
}

function buildResponsePayload({
  c,
  payrollClose = null,
  ytd = null,
  isPreview = false,
  otLockResult = null,
}) {
  const rowLike = payrollClose || buildPayrollClosePayload(c);

  return {
    ok: true,
    preview: isPreview,
    backendOnly: true,
    payslipSummary: payrollClose
      ? buildPayslipSummary(payrollClose)
      : buildPayslipSummaryFromComputed(c),
    payrollClose,
    ytd,
    taxCalc: c.taxCalc,
    taxMode: c.taxMode,
    taxUserId: c.resolved?.employeeUserId || "",
    taxUserIdSource: c.resolved?.source || "skipped",
    warning: c.warning,
    otLockResult,
    ssoPolicy: {
      enabled: c.ssoConfig.enabled,
      employeeRate: c.ssoConfig.employeeRate,
      maxWageBase: c.ssoConfig.maxWageBase,
      maxEmployeeMonthly: c.ssoConfig.maxEmployeeMonthly,
    },
    otSummary: {
      monthKey: c.otSummary.monthKey,
      approvedMinutes: c.otSummary.approvedMinutes,
      approvedWeightedHours: c.otSummary.approvedWeightedHours,
      count: c.otSummary.count,
      bySource: c.otSummary.bySource || {},
      records: c.otSummary.records,
    },
    displaySnapshot: {
      netBeforeOt: c.display.displayNetBeforeOt,
      leaveDeduction: c.display.displayLeaveDeduction,
      otHours: c.display.displayOtHours,
      otAmount: c.display.displayOtAmount,
      grossBeforeTax: c.display.displayGrossBeforeTax,
      taxAmount: c.display.displayTaxAmount,
      ssoAmount: c.display.displaySsoAmount,
      pvdAmount: c.display.displayPvdAmount,
      netPay: c.display.displayNetPay,
      salaryBaseForSso: c.display.displaySalaryBaseForSso,
    },
    grossBaseMode: {
      requested: normalizeGrossBaseMode(c.grossBaseMode),
      applied: c.payrollResolved.appliedMode,
      expectedGrossBeforeTax: 0,
      preDeductionNetBeforeTax: c.payrollResolved.preDeductionNetBeforeTax,
      postDeductionNetBeforeTax: c.payrollResolved.postDeductionNetBeforeTax,
    },
    payrollInputsResolved: {
      employeeId: c.employeeId,
      clinicId: c.clinicId,
      month: c.month,
      grossBase: c.grossBaseFinal,
      grossBaseSource: c.salaryProfile.grossBaseSource,
      employmentType: c.salaryProfile.employmentType,
      hourlyRate: c.salaryProfile.hourlyRate,
      monthlySalaryFromStaff: c.salaryProfile.monthlySalaryFromStaff,
      regularWork: c.salaryProfile.regularWork,
      attendanceRegularWork: c.salaryProfile.attendanceRegularWork || null,
      bodyRegularWork: c.salaryProfile.bodyRegularWork || null,
      bonus: c.bonusFinal,
      otherAllowance: c.otherAllowanceFinal,
      otherDeduction: c.otherDeductionFinal,
      leaveDeductionResolved: c.leaveDeductionResolved,
      pvdEmployeeMonthly: c.pvdM,
      ignoredClientInputs: c.ignoredClientInputs,
    },
    row: rowLike,
  };
}

function handleControllerError(res, err, label) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({
      ok: false,
      message: err.message,
      details: err.details,
    });
  }

  console.error(`${label} error:`, err);
  return res.status(500).json({
    ok: false,
    message: `${label} failed`,
    error: err.message,
  });
}

// ================= PREVIEW MONTH =================
// ✅ POST /payroll-close/preview/:employeeId/:month
async function previewMonth(req, res) {
  try {
    const body = req.body || {};
    const { clinicId: clinicIdFromToken } = assertAdminContext(req);

    const clinicId = safeStr(body.clinicId || clinicIdFromToken);
    const employeeId = safeStr(body.employeeId || req.params.employeeId);
    const month = safeStr(body.month || req.params.month);

    if (!clinicId || !employeeId || !month) {
      return res
        .status(400)
        .json({ message: "clinicId, employeeId, month is required" });
    }

    if (!isYm(month)) {
      return res.status(400).json({ message: "month must be yyyy-MM" });
    }

    const c = await computePayrollForMonth({
      req,
      clinicId,
      employeeId,
      month,
      body,
    });

    return res.json(buildResponsePayload({ c, isPreview: true }));
  } catch (err) {
    return handleControllerError(res, err, "previewMonth");
  }
}

// ================= CLOSE MONTH =================
async function closeMonth(req, res) {
  try {
    const body = req.body || {};

    const clinicId = safeStr(body.clinicId);
    const employeeId = safeStr(body.employeeId || req.params.employeeId);
    const month = safeStr(body.month || req.params.month);

    if (!clinicId || !employeeId || !month) {
      return res
        .status(400)
        .json({ message: "clinicId, employeeId, month is required" });
    }

    if (!isYm(month)) {
      return res.status(400).json({ message: "month must be yyyy-MM" });
    }

    const { clinicId: clinicIdFromToken } = assertAdminContext(req);

    if (safeStr(clinicId) !== clinicIdFromToken) {
      return res.status(403).json({ message: "Forbidden (clinic mismatch)" });
    }

    const existed = await PayrollClose.findOne({
      clinicId: clinicIdFromToken,
      employeeId,
      month,
    }).lean();

    if (existed) {
      return res.status(409).json({ message: "Month already closed" });
    }

    const c = await computePayrollForMonth({
      req,
      clinicId: clinicIdFromToken,
      employeeId,
      month,
      body,
    });

    let ytd = await TaxYTD.findOne({ employeeId, taxYear: c.taxYear });

    if (!ytd) {
      ytd = await TaxYTD.create({
        employeeId,
        taxYear: c.taxYear,
        incomeYTD: 0,
        ssoYTD: 0,
        pvdYTD: 0,
        taxPaidYTD: 0,
      });
    }

    const payrollClosePayload = buildPayrollClosePayload(c);
    const payrollClose = await PayrollClose.create(payrollClosePayload);

    ytd.incomeYTD = c.incomeYTD_after;
    ytd.ssoYTD = c.ssoYTD_after;
    ytd.pvdYTD = c.pvdYTD_after;

    if (c.taxMode === "WITHHOLDING") {
      ytd.taxPaidYTD = round2(c.ytdBefore.taxPaidYTD + c.withheldTaxMonthly);
    } else {
      ytd.taxPaidYTD = round2(c.ytdBefore.taxPaidYTD);
    }

    await ytd.save();

    const otLockResult = await lockOtRowsForPayrollClose({
      c,
      payrollClose,
    });

    return res.json(
      buildResponsePayload({
        c,
        payrollClose,
        ytd,
        isPreview: false,
        otLockResult,
      })
    );
  } catch (err) {
    return handleControllerError(res, err, "closeMonth");
  }
}

// ================= RECALCULATE / RE-CLOSE MONTH =================
function makeCaptureRes() {
  return {
    statusCode: 200,
    payload: null,
    sent: false,

    status(code) {
      this.statusCode = code;
      return this;
    },

    json(data) {
      this.payload = data;
      this.sent = true;
      return this;
    },
  };
}

function getClosedPayrollContributions(row) {
  const taxMode = normalizeTaxMode(row?.taxMode);

  return {
    taxYear: Number(row?.snapshot?.taxYear) || monthToTaxYear(row?.month),
    income: round2(clampMin0(row?.grossMonthly)),
    sso: round2(clampMin0(row?.ssoEmployeeMonthly)),
    pvd: round2(clampMin0(row?.pvdEmployeeMonthly)),
    taxPaid:
      taxMode === "WITHHOLDING"
        ? round2(clampMin0(row?.withheldTaxMonthly))
        : 0,
  };
}

async function rollbackTaxYtdFromClosedPayroll(row) {
  const employeeId = safeStr(row?.employeeId);
  const c = getClosedPayrollContributions(row);

  if (!employeeId || !c.taxYear) {
    return {
      ok: false,
      reason: "missing_employee_or_tax_year",
    };
  }

  const ytd = await TaxYTD.findOne({ employeeId, taxYear: c.taxYear });

  if (!ytd) {
    return {
      ok: true,
      reason: "tax_ytd_not_found_skip_rollback",
      employeeId,
      taxYear: c.taxYear,
    };
  }

  ytd.incomeYTD = round2(Math.max(0, clampMin0(ytd.incomeYTD) - c.income));
  ytd.ssoYTD = round2(Math.max(0, clampMin0(ytd.ssoYTD) - c.sso));
  ytd.pvdYTD = round2(Math.max(0, clampMin0(ytd.pvdYTD) - c.pvd));
  ytd.taxPaidYTD = round2(Math.max(0, clampMin0(ytd.taxPaidYTD) - c.taxPaid));

  await ytd.save();

  return {
    ok: true,
    action: "rollback",
    employeeId,
    taxYear: c.taxYear,
    subtracted: c,
    ytd: {
      incomeYTD: ytd.incomeYTD,
      ssoYTD: ytd.ssoYTD,
      pvdYTD: ytd.pvdYTD,
      taxPaidYTD: ytd.taxPaidYTD,
    },
  };
}

async function applyTaxYtdFromClosedPayroll(row) {
  const employeeId = safeStr(row?.employeeId);
  const c = getClosedPayrollContributions(row);

  if (!employeeId || !c.taxYear) {
    return {
      ok: false,
      reason: "missing_employee_or_tax_year",
    };
  }

  let ytd = await TaxYTD.findOne({ employeeId, taxYear: c.taxYear });

  if (!ytd) {
    ytd = await TaxYTD.create({
      employeeId,
      taxYear: c.taxYear,
      incomeYTD: 0,
      ssoYTD: 0,
      pvdYTD: 0,
      taxPaidYTD: 0,
    });
  }

  ytd.incomeYTD = round2(clampMin0(ytd.incomeYTD) + c.income);
  ytd.ssoYTD = round2(clampMin0(ytd.ssoYTD) + c.sso);
  ytd.pvdYTD = round2(clampMin0(ytd.pvdYTD) + c.pvd);
  ytd.taxPaidYTD = round2(clampMin0(ytd.taxPaidYTD) + c.taxPaid);

  await ytd.save();

  return {
    ok: true,
    action: "restore_apply",
    employeeId,
    taxYear: c.taxYear,
    added: c,
    ytd: {
      incomeYTD: ytd.incomeYTD,
      ssoYTD: ytd.ssoYTD,
      pvdYTD: ytd.pvdYTD,
      taxPaidYTD: ytd.taxPaidYTD,
    },
  };
}

function buildRecalculateBody({ req, oldRow, clinicId, employeeId, month }) {
  const body = req.body || {};

  return {
    ...body,

    clinicId,
    employeeId,
    month,

    __oldPayrollDefaults: {
      grossBase: oldRow?.grossBase ?? 0,
      bonus: oldRow?.bonus ?? 0,
      otherAllowance: oldRow?.otherAllowance ?? 0,
      otherDeduction: oldRow?.otherDeduction ?? 0,
      pvdEmployeeMonthly: oldRow?.pvdEmployeeMonthly ?? 0,
      ssoEmployeeMonthly: oldRow?.ssoEmployeeMonthly ?? 0,
      taxMode: oldRow?.taxMode || "WITHHOLDING",
      grossBaseMode:
        oldRow?.snapshot?.grossBaseModeRequested ||
        oldRow?.snapshot?.grossBaseModeApplied ||
        "PRE_DEDUCTION",
    },

    grossBase:
      body.grossBase !== undefined ? body.grossBase : oldRow?.grossBase ?? 0,

    // ✅ OT must be recalculated from Overtime rows again.
    // client otPay remains ignored unless explicit override is sent.
    otPay: body.otPay !== undefined ? body.otPay : 0,
    allowManualOtPayOverride: body.allowManualOtPayOverride === true,

    ssoEmployeeMonthly:
      body.ssoEmployeeMonthly !== undefined
        ? body.ssoEmployeeMonthly
        : oldRow?.ssoEmployeeMonthly ?? 0,

    taxMode: body.taxMode || oldRow?.taxMode || "WITHHOLDING",

    grossBaseMode:
      body.grossBaseMode ||
      oldRow?.snapshot?.grossBaseModeRequested ||
      oldRow?.snapshot?.grossBaseModeApplied ||
      "PRE_DEDUCTION",
  };
}

// ✅ POST /payroll-close/recalculate/:employeeId/:month
async function recalculateClosedMonth(req, res) {
  const { clinicId: clinicIdFromToken, userId: adminUserId, role } =
    pickAuth(req);

  try {
    if (!clinicIdFromToken) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    if (!adminUserId) {
      return res.status(401).json({ message: "Missing userId in token" });
    }

    if (!isAdminRole(role)) {
      return res.status(403).json({ message: "Forbidden (admin only)" });
    }

    const employeeId = safeStr(req.params.employeeId || req.body?.employeeId);
    const month = safeStr(req.params.month || req.body?.month);

    if (!employeeId) {
      return res.status(400).json({ message: "employeeId required" });
    }

    if (!isYm(month)) {
      return res.status(400).json({ message: "month must be yyyy-MM" });
    }

    const oldRow = await PayrollClose.findOne({
      clinicId: clinicIdFromToken,
      employeeId,
      month,
    }).lean();

    if (!oldRow) {
      return res.status(404).json({
        message: "Closed payroll not found",
        employeeId,
        month,
      });
    }

    console.log("[PAYROLL_RECALCULATE][START]", {
      clinicId: clinicIdFromToken,
      employeeId,
      month,
      oldPayrollCloseId: String(oldRow._id),
      adminUserId,
    });

    const rollbackResult = await rollbackTaxYtdFromClosedPayroll(oldRow);

    await PayrollClose.deleteOne({ _id: oldRow._id });

    const originalBody = req.body;
    const originalParams = req.params;

    req.body = buildRecalculateBody({
      req,
      oldRow,
      clinicId: clinicIdFromToken,
      employeeId,
      month,
    });

    req.params = {
      ...originalParams,
      employeeId,
      month,
    };

    const captureRes = makeCaptureRes();
    await closeMonth(req, captureRes);

    req.body = originalBody;
    req.params = originalParams;

    if (captureRes.statusCode >= 200 && captureRes.statusCode < 300) {
      console.log("[PAYROLL_RECALCULATE][SUCCESS]", {
        clinicId: clinicIdFromToken,
        employeeId,
        month,
        oldPayrollCloseId: String(oldRow._id),
        newPayrollCloseId: String(captureRes.payload?.payrollClose?._id || ""),
        otLockResult: captureRes.payload?.otLockResult || null,
      });

      return res.status(200).json({
        ok: true,
        recalculated: true,
        backendOnly: true,
        message: "Payroll month recalculated successfully",
        oldPayrollCloseId: String(oldRow._id),
        rollbackResult,
        result: captureRes.payload,
      });
    }

    let restoreResult = null;
    let ytdRestoreResult = null;

    try {
      const current = await PayrollClose.findOne({
        clinicId: clinicIdFromToken,
        employeeId,
        month,
      }).lean();

      if (!current) {
        await PayrollClose.create(oldRow);
        ytdRestoreResult = await applyTaxYtdFromClosedPayroll(oldRow);
        restoreResult = { ok: true, action: "old_payroll_restored" };
      } else {
        restoreResult = {
          ok: false,
          reason: "new_payroll_exists_after_failed_close",
          currentPayrollCloseId: String(current._id),
        };
      }
    } catch (restoreErr) {
      restoreResult = {
        ok: false,
        reason: "restore_failed",
        error: restoreErr.message,
      };
    }

    console.error("[PAYROLL_RECALCULATE][FAILED]", {
      clinicId: clinicIdFromToken,
      employeeId,
      month,
      closeStatus: captureRes.statusCode,
      closePayload: captureRes.payload,
      restoreResult,
      ytdRestoreResult,
    });

    return res.status(captureRes.statusCode || 500).json({
      ok: false,
      message: "Recalculate failed",
      oldPayrollCloseId: String(oldRow._id),
      rollbackResult,
      restoreResult,
      ytdRestoreResult,
      closeMonthResponse: captureRes.payload,
    });
  } catch (err) {
    console.error("recalculateClosedMonth error:", err);

    return res.status(500).json({
      ok: false,
      message: "recalculateClosedMonth failed",
      error: err.message,
    });
  }
}

// ✅ GET /payroll-close/close-months/:employeeId
async function getClosedMonthsByEmployee(req, res) {
  try {
    const { clinicId } = pickAuth(req);

    if (!clinicId) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    const employeeId = safeStr(req.params.employeeId);

    if (!employeeId) {
      return res.status(400).json({ message: "employeeId required" });
    }

    const rows = await PayrollClose.find({ clinicId, employeeId })
      .sort({ month: -1 })
      .lean();

    const items = rows.map((row) => ({
      ...row,
      payslipSummary: buildPayslipSummary(row),
    }));

    return res.json({ ok: true, rows: items });
  } catch (err) {
    return res.status(500).json({
      message: "getClosedMonthsByEmployee failed",
      error: err.message,
    });
  }
}

// ✅ GET /payroll-close/close-month/:employeeId/:month
async function getClosedMonthByEmployeeAndMonth(req, res) {
  try {
    const { clinicId } = pickAuth(req);

    if (!clinicId) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    const employeeId = safeStr(req.params.employeeId);
    const month = safeStr(req.params.month);

    if (!employeeId) {
      return res.status(400).json({ message: "employeeId required" });
    }

    if (!isYm(month)) {
      return res.status(400).json({ message: "month must be yyyy-MM" });
    }

    const row = await PayrollClose.findOne({
      clinicId,
      employeeId,
      month,
    }).lean();

    if (!row) {
      return res.status(404).json({ message: "Not found" });
    }

    const payslipSummary = buildPayslipSummary(row);

    return res.json({
      ok: true,
      payslipSummary,
      row,
    });
  } catch (err) {
    return res.status(500).json({
      message: "getClosedMonthByEmployeeAndMonth failed",
      error: err.message,
    });
  }
}

module.exports = {
  guardPayslipAccess,
  previewMonth,
  closeMonth,
  recalculateClosedMonth,
  getClosedMonthsByEmployee,
  getClosedMonthByEmployeeAndMonth,
};
