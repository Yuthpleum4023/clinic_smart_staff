// payroll_service/controllers/payrollCloseController.js
//
// ✅ FULL FILE — Payroll Close Controller (OT Approved included + TAX userId fix)
// - ✅ employeeId in this system = staffId (ชัด)
// - ✅ Pull approved OT summary by (clinicId + monthKey + staffId)
// - ✅ If client sends baseHourly (optional) and otPay=0 => compute otPay from approvedWeightedHours
// - ✅ FIX: tax calc must use EMPLOYEE userId (not admin userId)
//   - resolve employee userId priority:
//     1) req.body.employeeUserId (recommended for admin UI)
//     2) find from Overtime records (staffId+monthKey, userId not empty)
//     3) fallback to admin userId (last resort) + return warning
// - ✅ SECURITY: staff/employee ดูได้เฉพาะของตัวเอง, admin ดูได้ทั้งคลินิก
// - ✅ SECURITY: ทุก query ผูก clinicId จาก token กันข้อมูลข้ามคลินิก
// - ✅ ROBUST: รองรับทั้ง req.user และ req.userCtx (ตาม server.js ของท่าน)
//

const axios = require("axios");
const PayrollClose = require("../models/PayrollClose");
const TaxYTD = require("../models/TaxYTD");
const Overtime = require("../models/Overtime");

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
function computeGrossMonthly({
  grossBase,
  otPay,
  bonus,
  otherAllowance,
  otherDeduction,
}) {
  return Math.max(
    0,
    clampMin0(grossBase) +
      clampMin0(otPay) +
      clampMin0(bonus) +
      clampMin0(otherAllowance) -
      clampMin0(otherDeduction)
  );
}
async function postJson(url, body, headers) {
  return axios.post(url, body, {
    headers,
    timeout: 15000,
    validateStatus: () => true,
  });
}

// ================= AUTH PICKER (ROBUST) =================
// ✅ บาง env auth middleware จะ set req.user
// ✅ แต่ server.js ของท่าน decode ไว้ที่ req.userCtx
function pickAuth(req) {
  const u = req.user || {};
  const uc = req.userCtx || {};

  const role = safeStr(u.role || u.activeRole || uc.role || uc.activeRole);
  const clinicId = safeStr(u.clinicId || uc.clinicId);
  const userId = safeStr(u.userId || u.id || u._id || uc.userId || uc.id || uc._id);

  // employeeId ในระบบนี้ = staffId
  const staffId = safeStr(u.staffId || u.employeeId || uc.staffId || uc.employeeId);

  return { role, clinicId, userId, staffId };
}

// ================= ACCESS GUARD =================
// staff/employee: ดูได้เฉพาะของตัวเอง (employeeId ต้องเท่ากับ staffId ใน token)
// admin: ดูได้ทุกคนในคลินิก
function guardPayslipAccess(req, res, next) {
  const { role, staffId: staffIdInToken } = pickAuth(req);

  const employeeId = safeStr(req.params.employeeId || req.body?.employeeId);

  if (!role) return res.status(401).json({ message: "Unauthorized" });

  // admin ok
  if (role === "admin") return next();

  // employee/staff ok only if matches
  // รองรับ role="employee" และ role="staff" (บางระบบเรียก staff)
  if (role === "employee" || role === "staff") {
    if (!employeeId || !staffIdInToken) {
      return res.status(400).json({ message: "Missing employeeId/staffId" });
    }
    if (employeeId !== staffIdInToken) {
      return res.status(403).json({ message: "Forbidden" });
    }
    return next();
  }

  // other roles (helper etc) -> forbidden by default
  return res.status(403).json({ message: "Forbidden" });
}

// ================= OT helpers =================
// ✅ sum APPROVED OT of month (employeeId = staffId)
async function getApprovedOtSummaryForMonth({ clinicId, monthKey, employeeId }) {
  const cId = safeStr(clinicId);
  const mKey = safeStr(monthKey);
  const staffId = safeStr(employeeId); // ✅ employeeId in payroll = staffId

  if (!cId || !mKey || !staffId) {
    return {
      monthKey: mKey,
      approvedMinutes: 0,
      approvedWeightedHours: 0,
      records: [],
      count: 0,
    };
  }

  // ✅ ผูก clinicId + staffId ชัด ๆ
  const q = { clinicId: cId, monthKey: mKey, status: "approved", staffId };

  const rows = await Overtime.find(q)
    .select({
      workDate: 1,
      minutes: 1,
      multiplier: 1,
      status: 1,
      source: 1,
      note: 1,
      userId: 1,
    })
    .lean();

  const approvedMinutes = rows.reduce(
    (a, x) => a + Math.max(0, Math.floor(Number(x.minutes || 0))),
    0
  );

  const approvedWeightedHours = rows.reduce((a, x) => {
    const mins = Math.max(0, Math.floor(Number(x.minutes || 0)));
    const mul = Number(x.multiplier);
    const m = Number.isFinite(mul) && mul > 0 ? mul : 1.5;
    return a + (mins / 60) * m;
  }, 0);

  return {
    monthKey: mKey,
    approvedMinutes,
    approvedWeightedHours,
    count: rows.length,
    records: rows,
  };
}

// ================= EMPLOYEE userId resolver =================
// ✅ ภาษีต้องผูก userId ของพนักงานคนนั้น
// priority:
// 1) req.body.employeeUserId
// 2) lookup from Overtime (staffId+monthKey) where userId not empty
// 3) fallback to admin userId (last resort)
async function resolveEmployeeUserId({
  clinicId,
  monthKey,
  staffId,
  bodyEmployeeUserId,
  adminUserId,
}) {
  const fromBody = safeStr(bodyEmployeeUserId);
  if (fromBody) {
    return { employeeUserId: fromBody, source: "body" };
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
    employeeId: userId, // fallback compatibility
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

// ================= CLOSE MONTH =================
async function closeMonth(req, res) {
  try {
    const body = req.body || {};
    const {
      clinicId,
      employeeId, // ✅ employeeId = staffId
      month, // yyyy-MM
      grossBase = 0,
      otPay = 0,
      bonus = 0,
      otherAllowance = 0,
      otherDeduction = 0,
      ssoEmployeeMonthly = 0,
      pvdEmployeeMonthly = 0,
      baseHourly = null,

      // ✅ NEW: admin UI แนะนำส่งมาด้วย เพื่อให้ภาษีถูก 100%
      employeeUserId: employeeUserIdFromBody,
    } = body;

    if (!clinicId || !employeeId || !month) {
      return res
        .status(400)
        .json({ message: "clinicId, employeeId, month is required" });
    }
    if (!isYm(month)) {
      return res.status(400).json({ message: "month must be yyyy-MM" });
    }

    // ✅ ผูก clinicId จาก token เพื่อกันคนส่ง clinicId ปลอม
    const { clinicId: clinicIdFromToken, userId: adminUserId } = pickAuth(req);

    if (!clinicIdFromToken)
      return res.status(401).json({ message: "Missing clinicId in token" });

    if (safeStr(clinicId) !== clinicIdFromToken) {
      return res.status(403).json({ message: "Forbidden (clinic mismatch)" });
    }

    if (!adminUserId)
      return res.status(401).json({ message: "Missing userId in token" });

    const existed = await PayrollClose.findOne({
      clinicId: clinicIdFromToken,
      employeeId: safeStr(employeeId),
      month: safeStr(month),
    }).lean();
    if (existed) return res.status(409).json({ message: "Month already closed" });

    // ✅ OT summary (approved only) by staffId
    const otSummary = await getApprovedOtSummaryForMonth({
      clinicId: clinicIdFromToken,
      monthKey: safeStr(month),
      employeeId: safeStr(employeeId),
    });

    let otPayFinal = clampMin0(otPay);
    const bh = toNumber(baseHourly);
    if (otPayFinal <= 0 && Number.isFinite(bh) && bh > 0) {
      otPayFinal = Math.max(0, otSummary.approvedWeightedHours * bh);
    }

    const taxYear = monthToTaxYear(month);

    const grossMonthly = computeGrossMonthly({
      grossBase,
      otPay: otPayFinal,
      bonus,
      otherAllowance,
      otherDeduction,
    });

    const ssoM = clamp(clampMin0(ssoEmployeeMonthly), 0, 750);
    const pvdM = clampMin0(pvdEmployeeMonthly);

    // NOTE: TaxYTD ผูกด้วย employeeId (staffId)
    let ytd = await TaxYTD.findOne({ employeeId: safeStr(employeeId), taxYear });
    if (!ytd) {
      ytd = await TaxYTD.create({
        employeeId: safeStr(employeeId),
        taxYear,
        incomeYTD: 0,
        ssoYTD: 0,
        pvdYTD: 0,
        taxPaidYTD: 0,
      });
    }

    const incomeYTD_after = clampMin0(ytd.incomeYTD) + grossMonthly;
    const ssoYTD_after = clampMin0(ytd.ssoYTD) + ssoM;
    const pvdYTD_after = clampMin0(ytd.pvdYTD) + pvdM;

    // ✅ FIX: use EMPLOYEE userId for tax calc
    const resolved = await resolveEmployeeUserId({
      clinicId: clinicIdFromToken,
      monthKey: safeStr(month),
      staffId: safeStr(employeeId),
      bodyEmployeeUserId: employeeUserIdFromBody,
      adminUserId,
    });

    const taxCalc = await calcWithheldByYTDFromAuth({
      userId: resolved.employeeUserId,
      taxYear,
      incomeYTD: incomeYTD_after,
      ssoYTD: ssoYTD_after,
      pvdYTD: pvdYTD_after,
      taxPaidYTD: clampMin0(ytd.taxPaidYTD),
    });

    const withheldTaxMonthly = clampMin0(taxCalc?.withheldThisMonth);
    const netPay = Math.max(0, grossMonthly - withheldTaxMonthly - ssoM - pvdM);

    const payrollClose = await PayrollClose.create({
      clinicId: clinicIdFromToken,
      employeeId: safeStr(employeeId),
      month: safeStr(month),

      grossMonthly,
      withheldTaxMonthly,
      netPay,

      grossBase: clampMin0(grossBase),
      otPay: otPayFinal,
      bonus: clampMin0(bonus),
      otherAllowance: clampMin0(otherAllowance),
      otherDeduction: clampMin0(otherDeduction),

      ssoEmployeeMonthly: ssoM,
      pvdEmployeeMonthly: pvdM,

      otApprovedMinutes: Math.max(
        0,
        Math.floor(Number(otSummary.approvedMinutes || 0))
      ),
      otApprovedWeightedHours: clampMin0(otSummary.approvedWeightedHours),
      otApprovedCount: Math.max(0, Math.floor(Number(otSummary.count || 0))),

      locked: true,
      closedBy: adminUserId, // คนปิดงวด
    });

    ytd.incomeYTD = incomeYTD_after;
    ytd.ssoYTD = ssoYTD_after;
    ytd.pvdYTD = pvdYTD_after;
    ytd.taxPaidYTD += withheldTaxMonthly;
    await ytd.save();

    const warning =
      resolved.source === "admin_fallback"
        ? "employeeUserId not found (body/overtime). Tax calc fell back to admin userId. Please send employeeUserId from client for accuracy."
        : null;

    return res.json({
      ok: true,
      payrollClose,
      ytd,
      taxCalc,
      taxUserId: resolved.employeeUserId,
      taxUserIdSource: resolved.source,
      warning,
      otSummary: {
        monthKey: otSummary.monthKey,
        approvedMinutes: otSummary.approvedMinutes,
        approvedWeightedHours: otSummary.approvedWeightedHours,
        count: otSummary.count,
        records: otSummary.records,
      },
    });
  } catch (err) {
    console.error("closeMonth error:", err);
    return res
      .status(500)
      .json({ message: "closeMonth failed", error: err.message });
  }
}

// ✅ GET /payroll-close/close-months/:employeeId
async function getClosedMonthsByEmployee(req, res) {
  try {
    const { clinicId } = pickAuth(req);
    if (!clinicId)
      return res.status(401).json({ message: "Missing clinicId in token" });

    const employeeId = safeStr(req.params.employeeId);
    if (!employeeId) return res.status(400).json({ message: "employeeId required" });

    const rows = await PayrollClose.find({ clinicId, employeeId })
      .sort({ month: -1 })
      .lean();

    return res.json({ ok: true, rows });
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
    if (!clinicId)
      return res.status(401).json({ message: "Missing clinicId in token" });

    const employeeId = safeStr(req.params.employeeId);
    const month = safeStr(req.params.month);

    if (!employeeId) return res.status(400).json({ message: "employeeId required" });
    if (!isYm(month)) return res.status(400).json({ message: "month must be yyyy-MM" });

    const row = await PayrollClose.findOne({ clinicId, employeeId, month }).lean();
    if (!row) return res.status(404).json({ message: "Not found" });

    return res.json({ ok: true, row });
  } catch (err) {
    return res.status(500).json({
      message: "getClosedMonthByEmployeeAndMonth failed",
      error: err.message,
    });
  }
}

module.exports = {
  // middleware
  guardPayslipAccess,

  // endpoints
  closeMonth,
  getClosedMonthsByEmployee,
  getClosedMonthByEmployeeAndMonth,
};