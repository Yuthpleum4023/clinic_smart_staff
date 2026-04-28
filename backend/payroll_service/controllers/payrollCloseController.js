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
//                     + otherAllowance
//
//   Net สุดท้าย = Net ก่อนภาษี/PVD - ภาษี - PVD
//
// ✅ IMPORTANT:
// - SSO คิดจาก "ฐานเงินเดือน" เท่านั้น
// - SSO ไม่เอา OT / bonus / otherAllowance ไปคิด
// - otherDeduction ใน flow นี้ใช้เป็น "หักลา/ขาด" หลัก
// - otherAllowance ใช้เป็น commission/allowance bucket ได้
//
// ✅ UPDATED:
// - รวม OT จาก Overtime status=approved เท่านั้น
// - ใช้ approvedMinutes เป็นหลัก
// - full-time  => grossBase / 30 / 8
// - part-time  => hourlyRate/hourlyWage จาก staff_service
//
// ✅ NEW PRODUCTION:
// - เพิ่ม recalculateClosedMonth()
// - ใช้สำหรับ admin คำนวณงวดที่ปิดแล้วใหม่
// - rollback TaxYTD จาก PayrollClose เดิมก่อน
// - ลบ PayrollClose เดิม
// - เรียก closeMonth ใหม่จากข้อมูลล่าสุด
// - กัน YTD บวกซ้ำ
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

function normalizeEmploymentType(v) {
  const t = safeStr(v).toLowerCase();

  if (t === "parttime" || t === "part-time" || t === "part_time") {
    return "parttime";
  }

  if (t === "fulltime" || t === "full-time" || t === "full_time") {
    return "fulltime";
  }

  return "fulltime";
}

function resolvePartTimeHourlyFromEmployee(emp) {
  const candidates = [
    emp?.hourlyRate,
    emp?.hourlyWage,
    emp?.hourly_salary,
    emp?.hourly_salary_rate,
  ];

  for (const v of candidates) {
    const n = toNumber(v);
    if (n > 0) return round2(n);
  }

  return 0;
}

function computeFullTimeOtBaseHourly(grossBase) {
  const salaryBase = round2(clampMin0(grossBase));
  if (salaryBase <= 0) return 0;
  return round2(salaryBase / 30 / 8);
}

async function resolveOtBaseHourly({ employeeId, grossBase, authHeader }) {
  let employee = null;
  let staffLookupError = "";

  try {
    employee = await getEmployeeByStaffId(employeeId, authHeader);
  } catch (e) {
    staffLookupError = e?.message || "staff lookup failed";
    console.log("⚠️ resolveOtBaseHourly staff lookup failed:", staffLookupError);
  }

  const employmentType = normalizeEmploymentType(
    employee?.employmentType || employee?.employeeType || employee?.workType
  );

  let otBaseHourly = 0;
  let source = "";

  if (employmentType === "parttime") {
    otBaseHourly = resolvePartTimeHourlyFromEmployee(employee);
    source =
      otBaseHourly > 0 ? "staff_service.hourlyRate" : "missing_parttime_hourly";
  } else {
    otBaseHourly = computeFullTimeOtBaseHourly(grossBase);
    source = otBaseHourly > 0 ? "grossBase/30/8" : "missing_fulltime_grossBase";
  }

  return {
    employee,
    employmentType,
    otBaseHourly: round2(otBaseHourly),
    source,
    staffLookupError,
  };
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

function normalizeSsoEmployeeMonthly(v, maxEmployeeMonthly) {
  return round2(clamp(clampMin0(v), 0, clampMin0(maxEmployeeMonthly)));
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

  const q = {
    clinicId: cId,
    monthKey: mKey,
    status: "approved",
    $or: [{ staffId }, { principalId: staffId }],
  };

  const rows = await Overtime.find(q)
    .select({
      workDate: 1,
      minutes: 1,
      approvedMinutes: 1,
      multiplier: 1,
      status: 1,
      source: 1,
      note: 1,
      userId: 1,
      principalId: 1,
      staffId: 1,
      createdAt: 1,
    })
    .lean();

  const approvedMinutes = rows.reduce((a, x) => {
    const mins = Math.max(0, Math.floor(Number(x.approvedMinutes || 0)));
    return a + mins;
  }, 0);

  const approvedWeightedHours = rows.reduce((a, x) => {
    const mins = Math.max(0, Math.floor(Number(x.approvedMinutes || 0)));
    const mul = Number(x.multiplier);
    const m = Number.isFinite(mul) && mul > 0 ? mul : 1.5;
    return a + (mins / 60) * m;
  }, 0);

  return {
    monthKey: mKey,
    approvedMinutes,
    approvedWeightedHours: round2(approvedWeightedHours),
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

// ================= PAYSLIP SUMMARY =================
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

    const grossBaseFinal = round2(clampMin0(grossBase));
    const bonusFinal = round2(clampMin0(bonus));
    const otherAllowanceFinal = round2(clampMin0(otherAllowance));
    const otherDeductionFinal = round2(clampMin0(otherDeduction));

    const otRateResolved = await resolveOtBaseHourly({
      employeeId: safeStr(employeeId),
      grossBase: grossBaseFinal,
      authHeader: req.headers.authorization,
    });

    let otPayFinal = clampMin0(otPay);

    if (otPayFinal <= 0 && otRateResolved.otBaseHourly > 0) {
      otPayFinal = Math.max(
        0,
        otSummary.approvedWeightedHours * otRateResolved.otBaseHourly
      );
    }

    otPayFinal = round2(otPayFinal);

    console.log("[PAYROLL_CLOSE][OT_CALC]", {
      clinicId: clinicIdFromToken,
      employeeId: safeStr(employeeId),
      month: safeStr(month),
      employmentType: otRateResolved.employmentType,
      otBaseHourly: otRateResolved.otBaseHourly,
      otBaseHourlySource: otRateResolved.source,
      staffLookupError: otRateResolved.staffLookupError || "",
      approvedMinutes: otSummary.approvedMinutes,
      approvedWeightedHours: otSummary.approvedWeightedHours,
      otPayInput: round2(clampMin0(otPay)),
      otPayFinal,
    });

    const taxYear = monthToTaxYear(month);

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
        employmentTypeResolved: otRateResolved.employmentType,
        otBaseHourlyResolved: otRateResolved.otBaseHourly,
        otBaseHourlySource: otRateResolved.source,
        staffLookupError: otRateResolved.staffLookupError || "",
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

  const ytd = await TaxYTD.findOne({
    employeeId,
    taxYear: c.taxYear,
  });

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
  ytd.taxPaidYTD = round2(
    Math.max(0, clampMin0(ytd.taxPaidYTD) - c.taxPaid)
  );

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

  let ytd = await TaxYTD.findOne({
    employeeId,
    taxYear: c.taxYear,
  });

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

    grossBase:
      body.grossBase !== undefined ? body.grossBase : oldRow?.grossBase ?? 0,

    bonus: body.bonus !== undefined ? body.bonus : oldRow?.bonus ?? 0,

    otherAllowance:
      body.otherAllowance !== undefined
        ? body.otherAllowance
        : oldRow?.otherAllowance ?? 0,

    otherDeduction:
      body.otherDeduction !== undefined
        ? body.otherDeduction
        : oldRow?.otherDeduction ?? 0,

    pvdEmployeeMonthly:
      body.pvdEmployeeMonthly !== undefined
        ? body.pvdEmployeeMonthly
        : oldRow?.pvdEmployeeMonthly ?? 0,

    ssoEmployeeMonthly:
      body.ssoEmployeeMonthly !== undefined
        ? body.ssoEmployeeMonthly
        : oldRow?.ssoEmployeeMonthly ?? 0,

    // ถ้า admin ไม่ส่ง otPay มา ให้ closeMonth คำนวณจาก approved OT ล่าสุด
    otPay: body.otPay !== undefined ? body.otPay : 0,

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
  const { clinicId: clinicIdFromToken, userId: adminUserId, role } = pickAuth(
    req
  );

  try {
    if (!clinicIdFromToken) {
      return res.status(401).json({ message: "Missing clinicId in token" });
    }

    if (!adminUserId) {
      return res.status(401).json({ message: "Missing userId in token" });
    }

    if (role !== "admin") {
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
      });

      return res.status(200).json({
        ok: true,
        recalculated: true,
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
  closeMonth,
  recalculateClosedMonth,
  getClosedMonthsByEmployee,
  getClosedMonthByEmployeeAndMonth,
};