//
// payroll_service/controllers/payrollCloseController.js
//
// ✅ FULL FILE — Payroll Close Controller
// ✅ UPDATED TO MATCH BUSINESS FORMULA:
//
//   SSO = min(ฐานเงินเดือนที่ใช้คิด SSO, maxWageBase) * employeeRate
//
//   Net ก่อนภาษี/PVD = เงินเดือนฐาน
//                     - SSO
//                     - หักลา/ขาด
//                     + OT
//                     + bonus
//                     + otherAllowance (ใช้เป็น commission/allowance bucket ได้)
//
//   Net สุดท้าย = Net ก่อนภาษี/PVD - ภาษี - PVD
//
// ✅ IMPORTANT:
// - SSO คิดจาก "ฐานเงินเดือน" เท่านั้น
// - SSO ไม่เอา OT / bonus / otherAllowance ไปคิด
// - otherDeduction ใน flow นี้ใช้เป็น "หักลา/ขาด" หลัก
// - otherAllowance ใช้เป็น commission/allowance bucket ได้
//
// ✅ SAFE AGAINST DOUBLE-DEDUCTION:
// - PRE_DEDUCTION  = grossBase คือเงินเดือนฐานก่อนหักลา/ขาด
// - POST_DEDUCTION = grossBase คือเงินเดือนฐานหลังหักลา/ขาดแล้ว
// - AUTO           = ถ้ามี expected gross จาก client จะเลือกสูตรที่ใกล้ที่สุด
//
// ✅ TAX MODE:
// - WITHHOLDING
// - NO_WITHHOLDING
//
// ✅ SSO POLICY:
// - อ่านจาก Clinic.socialSecurity เป็นหลัก
// - fallback default:
//   - employeeRate = 0.05
//   - maxWageBase = 17500
//
// ✅ SNAPSHOT:
// - บันทึก display* fields ลง PayrollClose
// - บันทึก ssoBaseUsed และ policy ที่ใช้จริงลง snapshot
//
// ✅ NEW:
// - เพิ่ม payslipSummary เป็น contract กลางสำหรับ frontend/PDF
// - frontend สามารถใช้ payslipSummary.amounts ทางเดียวได้
// - ✅ รองรับ route ใหม่:
//   POST /payroll-close/close-month/:employeeId/:month
//

const axios = require("axios");
const PayrollClose = require("../models/PayrollClose");
const TaxYTD = require("../models/TaxYTD");
const Overtime = require("../models/Overtime");
const Clinic = require("../models/Clinic");

const { getEmployeeByStaffId } = require("../utils/staffClient");

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
function absDiff(a, b) {
  return Math.abs(toNumber(a) - toNumber(b));
}

// ================= GROSS BASE MODE =================
function normalizeGrossBaseMode(v) {
  const s = safeStr(v).toUpperCase();
  if (s === "POST_DEDUCTION") return "POST_DEDUCTION";
  if (s === "AUTO") return "AUTO";
  return "PRE_DEDUCTION";
}

function pickExpectedGrossBeforeTax(body) {
  const candidates = [
    body.expectedGrossBeforeTax,
    body.previewGrossBeforeTax,
    body.grossMonthlyExpected,
    body.displayGrossBeforeTax,
    body.detailGrossBeforeTax,
  ];

  for (const v of candidates) {
    const n = toNumber(v);
    if (n > 0) return round2(n);
  }
  return 0;
}

/**
 * BUSINESS FORMULA
 *
 * PRE_DEDUCTION:
 *   grossBase = เงินเดือนฐานก่อนหักลา/ขาด
 *   ssoBase   = grossBase
 *   netBeforeTaxAndPvd = grossBase - sso - otherDeduction + otPay + bonus + otherAllowance
 *
 * POST_DEDUCTION:
 *   grossBase = เงินเดือนฐานหลังหักลา/ขาดแล้ว
 *   ssoBase   = grossBase + otherDeduction   (reconstruct salary base for SSO)
 *   netBeforeTaxAndPvd = grossBase - sso + otPay + bonus + otherAllowance
 *
 * AUTO:
 *   เลือกสูตรที่ใกล้ expectedGrossBeforeTax มากกว่า
 */
function resolvePayrollComputation({
  body,
  grossBase,
  otPay,
  bonus,
  otherAllowance,
  otherDeduction,
}) {
  const requestedMode = normalizeGrossBaseMode(body.grossBaseMode);
  const expectedGrossBeforeTax = pickExpectedGrossBeforeTax(body);

  const salaryBasePreDeduction = round2(clampMin0(grossBase));
  const leaveDeduction = round2(clampMin0(otherDeduction));
  const otPayFinal = round2(clampMin0(otPay));
  const bonusFinal = round2(clampMin0(bonus));
  const allowanceFinal = round2(clampMin0(otherAllowance));

  const preDeductionSalaryBaseForSso = salaryBasePreDeduction;
  const preDeductionNetBeforeTax = round2(
    Math.max(
      0,
      salaryBasePreDeduction -
        leaveDeduction +
        otPayFinal +
        bonusFinal +
        allowanceFinal
    )
  );

  const postDeductionSalaryBaseAfterLeave = salaryBasePreDeduction;
  const postDeductionSalaryBaseForSso = round2(
    salaryBasePreDeduction + leaveDeduction
  );
  const postDeductionNetBeforeTax = round2(
    Math.max(
      0,
      postDeductionSalaryBaseAfterLeave +
        otPayFinal +
        bonusFinal +
        allowanceFinal
    )
  );

  const buildResult = (mode) => {
    if (mode === "POST_DEDUCTION") {
      return {
        appliedMode: "POST_DEDUCTION",
        expectedGrossBeforeTax,

        salaryBaseForSso: postDeductionSalaryBaseForSso,
        salaryBaseAfterLeave: postDeductionSalaryBaseAfterLeave,
        leaveDeduction,
        otPay: otPayFinal,
        bonus: bonusFinal,
        otherAllowance: allowanceFinal,

        netBeforeTaxAndPvd: postDeductionNetBeforeTax,

        preDeductionNetBeforeTax,
        postDeductionNetBeforeTax,
      };
    }

    return {
      appliedMode: "PRE_DEDUCTION",
      expectedGrossBeforeTax,

      salaryBaseForSso: preDeductionSalaryBaseForSso,
      salaryBaseAfterLeave: round2(
        Math.max(0, salaryBasePreDeduction - leaveDeduction)
      ),
      leaveDeduction,
      otPay: otPayFinal,
      bonus: bonusFinal,
      otherAllowance: allowanceFinal,

      netBeforeTaxAndPvd: preDeductionNetBeforeTax,

      preDeductionNetBeforeTax,
      postDeductionNetBeforeTax,
    };
  };

  if (requestedMode === "PRE_DEDUCTION") {
    return buildResult("PRE_DEDUCTION");
  }

  if (requestedMode === "POST_DEDUCTION") {
    return buildResult("POST_DEDUCTION");
  }

  if (expectedGrossBeforeTax > 0) {
    const preDiff = absDiff(preDeductionNetBeforeTax, expectedGrossBeforeTax);
    const postDiff = absDiff(postDeductionNetBeforeTax, expectedGrossBeforeTax);

    return buildResult(postDiff < preDiff ? "POST_DEDUCTION" : "PRE_DEDUCTION");
  }

  return buildResult("PRE_DEDUCTION");
}

// ================= SSO DEFAULTS =================
const DEFAULT_SSO_EMPLOYEE_RATE = 0.05;
const DEFAULT_SSO_MAX_WAGE_BASE = 17500;

// ================= TAX MODE =================
function normalizeTaxMode(v) {
  const s = safeStr(v).toUpperCase();
  if (s === "NO_WITHHOLDING") return "NO_WITHHOLDING";
  return "WITHHOLDING";
}

// เก็บไว้เผื่อ compatibility / debug
function normalizeSsoEmployeeMonthly(v, maxEmployeeMonthly) {
  return round2(clamp(clampMin0(v), 0, clampMin0(maxEmployeeMonthly)));
}

// ✅ อ่าน config SSO จาก clinic
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

// ✅ SSO คิดจาก "ฐานเงินเดือนที่ใช้คิด SSO" เท่านั้น
function computeSsoEmployeeMonthlyFromClinicConfig(salaryBaseForSso, ssoConfig) {
  if (!ssoConfig?.enabled) return 0;

  const contributableBase = Math.min(
    clampMin0(salaryBaseForSso),
    clampMin0(ssoConfig.maxWageBase)
  );

  return round2(contributableBase * clampMin0(ssoConfig.employeeRate));
}

// ================= AUTH PICKER (ROBUST) =================
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

// ================= ACCESS GUARD =================
function guardPayslipAccess(req, res, next) {
  const { role, staffId: staffIdInToken } = pickAuth(req);
  const employeeId = safeStr(req.params.employeeId || req.body?.employeeId);

  if (!role) return res.status(401).json({ message: "Unauthorized" });

  if (role === "admin") return next();

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
    };
  }

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
      createdAt: 1,
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
async function resolveEmployeeUserId({
  clinicId,
  monthKey,
  staffId,
  bodyEmployeeUserId,
  adminUserId,
  token,
}) {
  const fromBody = safeStr(bodyEmployeeUserId);
  if (fromBody) {
    return { employeeUserId: fromBody, source: "body" };
  }

  try {
    const emp = await getEmployeeByStaffId(staffId, token);
    const u = safeStr(emp?.userId);
    if (u) return { employeeUserId: u, source: "staff_service" };
  } catch (e) {
    console.log("⚠️ staff_service lookup failed:", e.message);
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

// ================= PAYSLIP SUMMARY (NEW SINGLE CONTRACT) =================
// ✅ IMPORTANT:
// summary ตัวนี้ใช้ "แสดงผล" อย่างเดียว
// ดังนั้นต้อง map จากค่าที่ lock ลง PayrollClose ตรง ๆ
// ไม่ต้อง derive salary จาก snapshot หลังหักอะไรแล้ว
function buildPayslipSummary(row) {
  const salary = round2(clampMin0(row?.grossBase));
  const socialSecurity = round2(clampMin0(row?.ssoEmployeeMonthly));
  const ot = round2(clampMin0(row?.otPay));
  const commission = round2(clampMin0(row?.otherAllowance));
  const bonus = round2(clampMin0(row?.bonus));
  const leaveDeduction = round2(clampMin0(row?.otherDeduction));
  const tax = round2(clampMin0(row?.withheldTaxMonthly));
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
      netPay,
    },
    meta: {
      source: "backend_final",
      isClosedPayroll: true,
      grossBaseModeApplied: safeStr(row?.snapshot?.grossBaseModeApplied),
    },
  };
}

// ================= CLOSE MONTH =================
async function closeMonth(req, res) {
  try {
    const body = req.body || {};

    const clinicId = safeStr(body.clinicId);
    const employeeId = safeStr(body.employeeId || req.params.employeeId);
    const month = safeStr(body.month || req.params.month);

    const grossBase = toNumber(body.grossBase);
    const otPay = toNumber(body.otPay);
    const bonus = toNumber(body.bonus);
    const otherAllowance = toNumber(body.otherAllowance);
    const otherDeduction = toNumber(body.otherDeduction);
    const ssoEmployeeMonthly = toNumber(body.ssoEmployeeMonthly);
    const pvdEmployeeMonthly = toNumber(body.pvdEmployeeMonthly);
    const baseHourly = body.baseHourly;
    const employeeUserIdFromBody = safeStr(body.employeeUserId);
    const taxModeRaw = body.taxMode;
    const grossBaseModeRaw = body.grossBaseMode;

    if (!clinicId || !employeeId || !month) {
      return res
        .status(400)
        .json({ message: "clinicId, employeeId, month is required" });
    }
    if (!isYm(month)) {
      return res.status(400).json({ message: "month must be yyyy-MM" });
    }

    const taxMode = normalizeTaxMode(taxModeRaw);

    const {
      clinicId: clinicIdFromToken,
      userId: adminUserId,
      role,
    } = pickAuth(req);

    if (!clinicIdFromToken) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    if (safeStr(clinicId) !== clinicIdFromToken) {
      return res.status(403).json({ message: "Forbidden (clinic mismatch)" });
    }

    if (!adminUserId) {
      return res.status(401).json({ message: "Missing userId in token" });
    }

    if (role !== "admin") {
      return res.status(403).json({ message: "Forbidden (admin only)" });
    }

    const existed = await PayrollClose.findOne({
      clinicId: clinicIdFromToken,
      employeeId: safeStr(employeeId),
      month: safeStr(month),
    }).lean();

    if (existed) {
      return res.status(409).json({ message: "Month already closed" });
    }

    const clinicRow = await Clinic.findOne({
      clinicId: clinicIdFromToken,
    }).lean();

    const ssoConfig = resolveClinicSsoConfig(clinicRow);

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
    otPayFinal = round2(otPayFinal);

    const taxYear = monthToTaxYear(month);

    const grossBaseFinal = round2(clampMin0(grossBase));
    const bonusFinal = round2(clampMin0(bonus));
    const otherAllowanceFinal = round2(clampMin0(otherAllowance));
    const otherDeductionFinal = round2(clampMin0(otherDeduction));

    const payrollResolved = resolvePayrollComputation({
      body,
      grossBase: grossBaseFinal,
      otPay: otPayFinal,
      bonus: bonusFinal,
      otherAllowance: otherAllowanceFinal,
      otherDeduction: otherDeductionFinal,
    });

    const salaryBaseForSso = round2(payrollResolved.salaryBaseForSso);
    const salaryBaseAfterLeave = round2(payrollResolved.salaryBaseAfterLeave);
    const leaveDeduction = round2(payrollResolved.leaveDeduction);

    const ssoM = computeSsoEmployeeMonthlyFromClinicConfig(
      salaryBaseForSso,
      ssoConfig
    );

    const pvdM = round2(clampMin0(pvdEmployeeMonthly));

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

    let ytd = await TaxYTD.findOne({
      employeeId: safeStr(employeeId),
      taxYear,
    });

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

    const incomeYTD_after = round2(
      clampMin0(ytd.incomeYTD) + netBeforeTaxAndPvd
    );
    const ssoYTD_after = round2(clampMin0(ytd.ssoYTD) + ssoM);
    const pvdYTD_after = round2(clampMin0(ytd.pvdYTD) + pvdM);

    let resolved = null;
    let taxCalc = null;
    let withheldTaxMonthly = 0;
    let warning = null;

    if (taxMode === "WITHHOLDING") {
      resolved = await resolveEmployeeUserId({
        clinicId: clinicIdFromToken,
        monthKey: safeStr(month),
        staffId: safeStr(employeeId),
        bodyEmployeeUserId: employeeUserIdFromBody,
        adminUserId,
        token: req.headers.authorization,
      });

      taxCalc = await calcWithheldByYTDFromAuth({
        userId: resolved.employeeUserId,
        taxYear,
        incomeYTD: incomeYTD_after,
        ssoYTD: ssoYTD_after,
        pvdYTD: pvdYTD_after,
        taxPaidYTD: clampMin0(ytd.taxPaidYTD),
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

    const payrollClosePayload = {
      clinicId: clinicIdFromToken,
      employeeId: safeStr(employeeId),
      month: safeStr(month),

      grossMonthly,
      withheldTaxMonthly,
      netPay,

      grossBase: grossBaseFinal,
      otPay: otPayFinal,
      bonus: bonusFinal,
      otherAllowance: otherAllowanceFinal,
      otherDeduction: otherDeductionFinal,

      ssoEmployeeMonthly: ssoM,
      pvdEmployeeMonthly: pvdM,

      otApprovedMinutes: Math.max(
        0,
        Math.floor(Number(otSummary.approvedMinutes || 0))
      ),
      otApprovedWeightedHours: round2(
        clampMin0(otSummary.approvedWeightedHours)
      ),
      otApprovedCount: Math.max(0, Math.floor(Number(otSummary.count || 0))),

      displayNetBeforeOt: display.displayNetBeforeOt,
      displayLeaveDeduction: display.displayLeaveDeduction,
      displayOtHours: display.displayOtHours,
      displayOtAmount: display.displayOtAmount,
      displayGrossBeforeTax: display.displayGrossBeforeTax,
      displayTaxAmount: display.displayTaxAmount,
      displaySsoAmount: display.displaySsoAmount,
      displayNetPay: display.displayNetPay,

      locked: true,
      closedBy: adminUserId,
      taxMode,

      snapshot: {
        taxYear,
        allowanceTotalAnnual: 0,
        incomeYTD_after,
        ssoYTD_after,
        pvdYTD_after,
        taxableYTD: round2(clampMin0(taxCalc?.taxableYTD)),
        taxDueYTD: round2(clampMin0(taxCalc?.taxDueYTD)),
        taxPaidYTD_before: round2(clampMin0(ytd.taxPaidYTD)),
        taxPaidYTD_after:
          taxMode === "WITHHOLDING"
            ? round2(clampMin0(ytd.taxPaidYTD) + withheldTaxMonthly)
            : round2(clampMin0(ytd.taxPaidYTD)),

        grossBaseModeRequested: normalizeGrossBaseMode(grossBaseModeRaw),
        grossBaseModeApplied: payrollResolved.appliedMode,
        expectedGrossBeforeTax: payrollResolved.expectedGrossBeforeTax,
        preDeductionNetBeforeTax: payrollResolved.preDeductionNetBeforeTax,
        postDeductionNetBeforeTax: payrollResolved.postDeductionNetBeforeTax,

        ssoBaseUsed: salaryBaseForSso,
        salaryBaseAfterLeave,
        leaveDeduction,
        otPayUsed: otPayFinal,
        bonusUsed: bonusFinal,
        otherAllowanceUsed: otherAllowanceFinal,
        netBeforeTaxAndPvd,

        ssoEnabled: ssoConfig.enabled,
        ssoRate: ssoConfig.employeeRate,
        ssoMaxWageBase: ssoConfig.maxWageBase,
        ssoMaxEmployeeMonthly: ssoConfig.maxEmployeeMonthly,
        ssoEmployeeMonthlyInput: normalizeSsoEmployeeMonthly(
          ssoEmployeeMonthly,
          ssoConfig.maxEmployeeMonthly
        ),
        ssoEmployeeMonthlyApplied: ssoM,
      },
    };

    const payrollClose = await PayrollClose.create(payrollClosePayload);
    const payslipSummary = buildPayslipSummary(payrollClose);

    ytd.incomeYTD = incomeYTD_after;
    ytd.ssoYTD = ssoYTD_after;
    ytd.pvdYTD = pvdYTD_after;

    if (taxMode === "WITHHOLDING") {
      ytd.taxPaidYTD = round2(clampMin0(ytd.taxPaidYTD) + withheldTaxMonthly);
    } else {
      ytd.taxPaidYTD = round2(clampMin0(ytd.taxPaidYTD));
    }

    await ytd.save();

    return res.json({
      ok: true,
      payslipSummary,
      payrollClose,
      ytd,
      taxCalc,
      taxMode,
      taxUserId: resolved?.employeeUserId || "",
      taxUserIdSource: resolved?.source || "skipped",
      warning,
      ssoPolicy: {
        enabled: ssoConfig.enabled,
        employeeRate: ssoConfig.employeeRate,
        maxWageBase: ssoConfig.maxWageBase,
        maxEmployeeMonthly: ssoConfig.maxEmployeeMonthly,
      },
      otSummary: {
        monthKey: otSummary.monthKey,
        approvedMinutes: otSummary.approvedMinutes,
        approvedWeightedHours: otSummary.approvedWeightedHours,
        count: otSummary.count,
        records: otSummary.records,
      },
      displaySnapshot: {
        netBeforeOt: display.displayNetBeforeOt,
        leaveDeduction: display.displayLeaveDeduction,
        otHours: display.displayOtHours,
        otAmount: display.displayOtAmount,
        grossBeforeTax: display.displayGrossBeforeTax,
        taxAmount: display.displayTaxAmount,
        ssoAmount: display.displaySsoAmount,
        netPay: display.displayNetPay,
        salaryBaseForSso: display.displaySalaryBaseForSso,
      },
      grossBaseMode: {
        requested: normalizeGrossBaseMode(grossBaseModeRaw),
        applied: payrollResolved.appliedMode,
        expectedGrossBeforeTax: payrollResolved.expectedGrossBeforeTax,
        preDeductionNetBeforeTax: payrollResolved.preDeductionNetBeforeTax,
        postDeductionNetBeforeTax: payrollResolved.postDeductionNetBeforeTax,
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
  closeMonth,
  getClosedMonthsByEmployee,
  getClosedMonthByEmployeeAndMonth,
};