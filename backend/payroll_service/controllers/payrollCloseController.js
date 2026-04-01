//
// payroll_service/controllers/payrollCloseController.js
//
// ✅ FULL FILE — Payroll Close Controller
// ✅ PATCH SAFE AGAINST DOUBLE-DEDUCTION:
// - คง route / function names / response structure เดิม
// - กันความเสี่ยง "หักวันลา/ขาดซ้ำ" ด้วย grossBaseMode
// - รองรับ 3 โหมดของ grossBase:
//   1) PRE_DEDUCTION   = grossBase คือฐานก่อนหักลา/ขาด
//   2) POST_DEDUCTION  = grossBase คือฐานหลังหักลา/ขาดแล้ว
//   3) AUTO            = ถ้ามี expected gross จาก client จะเลือกสูตรที่ใกล้ที่สุด
// - default ยังคง backward-compatible = PRE_DEDUCTION
//
// ✅ TAX MODE:
// - WITHHOLDING
// - NO_WITHHOLDING
//
// ✅ NEW DISPLAY SNAPSHOT:
// - บันทึก display* fields ลง PayrollClose
// - เพื่อให้หน้า detail / preview / PDF ใช้เลขชุดเดียวกัน
//
// ✅ EXISTING FEATURES:
// - employeeId in this system = staffId
// - Pull approved OT summary by (clinicId + monthKey + staffId)
// - If client sends baseHourly and otPay=0 => compute otPay from approvedWeightedHours
// - TAX userId fix: use EMPLOYEE userId instead of admin userId
// - SECURITY: staff/employee ดูได้เฉพาะของตัวเอง, admin ดูได้ทั้งคลินิก
// - SECURITY: ทุก query ผูก clinicId จาก token กันข้อมูลข้ามคลินิก
// - ROBUST: รองรับทั้ง req.user และ req.userCtx
//
// ✅ SSO POLICY:
// - อ่านจาก Clinic.socialSecurity เป็นหลัก
// - fallback default:
//   - employeeRate = 0.05
//   - maxWageBase = 17500
// - backend คำนวณ SSO เองจาก grossMonthly
// - ไม่เชื่อ ssoEmployeeMonthly ที่ client ส่งมาเป็น source of truth
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

function computeGrossMonthlyPreDeduction({
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

function computeGrossMonthlyPostDeduction({
  grossBase,
  otPay,
  bonus,
  otherAllowance,
}) {
  return Math.max(
    0,
    clampMin0(grossBase) +
      clampMin0(otPay) +
      clampMin0(bonus) +
      clampMin0(otherAllowance)
  );
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

function resolveGrossComputation({
  body,
  grossBase,
  otPay,
  bonus,
  otherAllowance,
  otherDeduction,
}) {
  const requestedMode = normalizeGrossBaseMode(body.grossBaseMode);
  const expectedGrossBeforeTax = pickExpectedGrossBeforeTax(body);

  const preDeductionGross = round2(
    computeGrossMonthlyPreDeduction({
      grossBase,
      otPay,
      bonus,
      otherAllowance,
      otherDeduction,
    })
  );

  const postDeductionGross = round2(
    computeGrossMonthlyPostDeduction({
      grossBase,
      otPay,
      bonus,
      otherAllowance,
    })
  );

  if (requestedMode === "PRE_DEDUCTION") {
    return {
      effectiveGrossBase: round2(clampMin0(grossBase)),
      grossMonthly: preDeductionGross,
      appliedMode: "PRE_DEDUCTION",
      expectedGrossBeforeTax,
      preDeductionGross,
      postDeductionGross,
    };
  }

  if (requestedMode === "POST_DEDUCTION") {
    return {
      effectiveGrossBase: round2(clampMin0(grossBase)),
      grossMonthly: postDeductionGross,
      appliedMode: "POST_DEDUCTION",
      expectedGrossBeforeTax,
      preDeductionGross,
      postDeductionGross,
    };
  }

  if (expectedGrossBeforeTax > 0) {
    const preDiff = absDiff(preDeductionGross, expectedGrossBeforeTax);
    const postDiff = absDiff(postDeductionGross, expectedGrossBeforeTax);

    const appliedMode =
      postDiff < preDiff ? "POST_DEDUCTION" : "PRE_DEDUCTION";

    return {
      effectiveGrossBase: round2(clampMin0(grossBase)),
      grossMonthly:
        appliedMode === "POST_DEDUCTION"
          ? postDeductionGross
          : preDeductionGross,
      appliedMode,
      expectedGrossBeforeTax,
      preDeductionGross,
      postDeductionGross,
    };
  }

  // backward-compatible default
  return {
    effectiveGrossBase: round2(clampMin0(grossBase)),
    grossMonthly: preDeductionGross,
    appliedMode: "PRE_DEDUCTION",
    expectedGrossBeforeTax,
    preDeductionGross,
    postDeductionGross,
  };
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

// เก็บไว้เผื่อ compatibility / support อื่น ๆ
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

function computeSsoEmployeeMonthlyFromClinicConfig(grossMonthly, ssoConfig) {
  if (!ssoConfig?.enabled) return 0;

  const contributableBase = Math.min(
    clampMin0(grossMonthly),
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
  displayNetBeforeOtBase,
  otherDeduction,
  otSummary,
  otPayFinal,
  grossMonthly,
  withheldTaxMonthly,
  ssoM,
  pvdM,
  netPay,
}) {
  const displayNetBeforeOt = round2(clampMin0(displayNetBeforeOtBase));
  const displayLeaveDeduction = round2(clampMin0(otherDeduction));
  const displayOtHours = round2(clampMin0(otSummary?.approvedWeightedHours));
  const displayOtAmount = round2(clampMin0(otPayFinal));
  const displayGrossBeforeTax = round2(clampMin0(grossMonthly));
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
  };
}

// ================= CLOSE MONTH =================
async function closeMonth(req, res) {
  try {
    const body = req.body || {};
    const {
      clinicId,
      employeeId, // employeeId = staffId
      month, // yyyy-MM
      grossBase = 0,
      otPay = 0,
      bonus = 0,
      otherAllowance = 0,
      otherDeduction = 0,
      ssoEmployeeMonthly = 0, // รับไว้เพื่อ compatibility / debug
      pvdEmployeeMonthly = 0,
      baseHourly = null,
      employeeUserId: employeeUserIdFromBody,
      taxMode: taxModeRaw,
      grossBaseMode: grossBaseModeRaw,
    } = body;

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

    const grossResolved = resolveGrossComputation({
      body,
      grossBase: grossBaseFinal,
      otPay: otPayFinal,
      bonus: bonusFinal,
      otherAllowance: otherAllowanceFinal,
      otherDeduction: otherDeductionFinal,
      grossBaseMode: grossBaseModeRaw,
    });

    const grossMonthly = round2(grossResolved.grossMonthly);

    // ✅ backend คำนวณเองจาก clinic config
    const ssoM = computeSsoEmployeeMonthlyFromClinicConfig(
      grossMonthly,
      ssoConfig
    );

    const pvdM = round2(clampMin0(pvdEmployeeMonthly));

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

    const incomeYTD_after = round2(clampMin0(ytd.incomeYTD) + grossMonthly);
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
      Math.max(0, grossMonthly - withheldTaxMonthly - ssoM - pvdM)
    );

    const display = buildDisplaySnapshot({
      displayNetBeforeOtBase: grossBaseFinal,
      otherDeduction: otherDeductionFinal,
      otSummary,
      otPayFinal,
      grossMonthly,
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

      // ✅ display snapshot fields
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

        // ✅ debug-safe trace for future support
        grossBaseModeRequested: normalizeGrossBaseMode(grossBaseModeRaw),
        grossBaseModeApplied: grossResolved.appliedMode,
        expectedGrossBeforeTax: grossResolved.expectedGrossBeforeTax,
        preDeductionGross: grossResolved.preDeductionGross,
        postDeductionGross: grossResolved.postDeductionGross,

        // ✅ SSO snapshot
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
      },
      grossBaseMode: {
        requested: normalizeGrossBaseMode(grossBaseModeRaw),
        applied: grossResolved.appliedMode,
        expectedGrossBeforeTax: grossResolved.expectedGrossBeforeTax,
        preDeductionGross: grossResolved.preDeductionGross,
        postDeductionGross: grossResolved.postDeductionGross,
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

    return res.json({ ok: true, row });
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