// backend/auth_user_service/controllers/payrollTaxController.js

const User = require("../models/User");

function toNumber(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function clampMin0(n) {
  return Math.max(0, toNumber(n));
}

/**
 * ✅ ระบบ JWT ของคุณใช้ userId (usr_...)
 * - รองรับ fallback เผื่อ middleware ส่ง field ชื่ออื่น
 */
function getUserId(req) {
  return (
    req.user?.userId ||
    req.user?.id ||
    req.user?._id ||
    req.userId ||
    req.body?.userId ||
    req.query?.userId
  );
}

function currentTaxYear() {
  return new Date().getFullYear();
}

function isInternalRequest(req) {
  const key = String(req.headers["x-internal-key"] || "");
  const expected = String(process.env.INTERNAL_SERVICE_KEY || "");
  return expected && key && key === expected;
}

function isObjectIdString(s) {
  const v = String(s || "").trim();
  return /^[a-fA-F0-9]{24}$/.test(v);
}

// ----------------------
// Progressive tax (TH)
// ----------------------
function calcProgressiveTax(annualTaxableIncome) {
  const income = Math.max(0, toNumber(annualTaxableIncome));

  const brackets = [
    { upTo: 150000, rate: 0.0 },
    { upTo: 300000, rate: 0.05 },
    { upTo: 500000, rate: 0.1 },
    { upTo: 750000, rate: 0.15 },
    { upTo: 1000000, rate: 0.2 },
    { upTo: 2000000, rate: 0.25 },
    { upTo: 5000000, rate: 0.3 },
    { upTo: Infinity, rate: 0.35 },
  ];

  let tax = 0;
  let prev = 0;

  for (const b of brackets) {
    const cap = b.upTo;
    const portion = Math.max(0, Math.min(income, cap) - prev);
    tax += portion * b.rate;
    prev = cap;
    if (income <= cap) break;
  }

  return Math.max(0, tax);
}

// ----------------------
// Allowance calculator (MVP)
// - ตอนนี้คงไว้แบบง่าย เพื่อไม่ให้พัง
// - ถ้าคุณมี profile เต็มอยู่แล้ว เดี๋ยวค่อยเอากลับมาได้
// ----------------------
function calcAllowanceFromProfile(profile) {
  const p = profile || {};

  // ✅ ค่าเริ่มต้นตามที่ UI โชว์: ลดหย่อนพื้นฐาน 60,000
  // (สามารถขยายภายหลัง)
  const allowanceTotal = 60000;

  return { allowanceTotal };
}

/**
 * ✅ PUBLIC (สำหรับ App)
 * POST /users/me/payroll/calc-tax?year=YYYY
 *
 * Body:
 * {
 *   "grossMonthly": number,
 *   "monthsPerYear": 12,
 *   "ssoEmployeeMonthly": number,
 *   "pvdEmployeeMonthly": number
 * }
 */
exports.calcMyMonthlyTaxFromProfile = async (req, res) => {
  try {
    const userId = String(getUserId(req) || "").trim();

    if (!userId) {
      console.log("❌ TAX(calcMyMonthlyTaxFromProfile) → userId missing", req.user);
      return res.status(401).json({ message: "Unauthorized" });
    }

    const year = Number(req.query.year) || currentTaxYear();

    const grossMonthly = clampMin0(req.body?.grossMonthly ?? 0);
    const monthsPerYear = Math.max(
      1,
      Math.min(12, Number(req.body?.monthsPerYear || 12))
    );

    const ssoEmployeeMonthly = clampMin0(req.body?.ssoEmployeeMonthly ?? 0);
    const pvdEmployeeMonthly = clampMin0(req.body?.pvdEmployeeMonthly ?? 0);

    if (!grossMonthly) {
      return res.status(400).json({ message: "grossMonthly required" });
    }

    // ✅ สำคัญ: ระบบคุณใช้ userId (usr_...) ไม่ใช่ Mongo _id
    const user = await User.findOne({ userId }).select("taxProfiles").lean();
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const profile =
      (user.taxProfiles || []).find((p) => Number(p.taxYear) === year) || null;

    const { allowanceTotal } = calcAllowanceFromProfile(profile);

    const projectedAnnualIncome = grossMonthly * monthsPerYear;
    const projectedAnnualContribDeductions =
      (ssoEmployeeMonthly + pvdEmployeeMonthly) * monthsPerYear;

    const projectedAnnualTaxable = Math.max(
      0,
      projectedAnnualIncome - allowanceTotal - projectedAnnualContribDeductions
    );

    const projectedAnnualTax = calcProgressiveTax(projectedAnnualTaxable);
    const estimatedMonthlyTax = projectedAnnualTax / monthsPerYear;

    const netAfterTaxMonthly = Math.max(0, grossMonthly - estimatedMonthlyTax);
    const netAfterTaxAndSSOMonthly = Math.max(
      0,
      grossMonthly - estimatedMonthlyTax - ssoEmployeeMonthly - pvdEmployeeMonthly
    );

    return res.json({
      taxYear: year,
      grossMonthly,
      monthsPerYear,
      ssoEmployeeMonthly,
      pvdEmployeeMonthly,
      estimatedMonthlyTax,
      netAfterTaxMonthly,
      netAfterTaxAndSSOMonthly,
      allowanceTotal,
    });
  } catch (err) {
    console.error("calcMyMonthlyTaxFromProfile error:", err);
    return res.status(500).json({ message: "Server error" });
  }
};

// ----------------------
// Internal YTD (🔥 HARDENED) - สำหรับ payroll_service ตอนปิดงวด
// POST /internal/payroll/calc-tax-ytd?year=YYYY
// Header: x-internal-key
//
// Body:
// {
//   "employeeId": "...",    // รองรับ: ObjectId / usr_... / emp_... / staffId
//   "incomeYTD": number,
//   "ssoYTD": number,
//   "pvdYTD": number,
//   "taxPaidYTD": number
// }
// ----------------------
exports.calcTaxYTDInternal = async (req, res) => {
  try {
    if (!isInternalRequest(req)) {
      return res.status(403).json({ message: "Forbidden (internal only)" });
    }

    const year = Number(req.query.year) || currentTaxYear();

    const employeeIdRaw = String(req.body?.employeeId || "").trim();
    if (!employeeIdRaw) {
      console.log("❌ TAX YTD → employeeId missing");
      return res.status(400).json({ message: "employeeId required" });
    }

    const incomeYTD = clampMin0(req.body?.incomeYTD ?? 0);
    const ssoYTD = clampMin0(req.body?.ssoYTD ?? 0);
    const pvdYTD = clampMin0(req.body?.pvdYTD ?? 0);
    const taxPaidYTD = clampMin0(req.body?.taxPaidYTD ?? 0);

    console.log("➡️ TAX YTD REQUEST", {
      year,
      employeeId: employeeIdRaw,
      incomeYTD,
      ssoYTD,
      pvdYTD,
      taxPaidYTD,
    });

    // ✅ Query ครั้งเดียว ครอบจักรวาล
    const query = {
      $or: [
        isObjectIdString(employeeIdRaw) ? { _id: employeeIdRaw } : null,
        { userId: employeeIdRaw },
        { employeeCode: employeeIdRaw },
        { staffId: employeeIdRaw },
      ].filter(Boolean),
    };

    const user = await User.findOne(query)
      .select("userId employeeCode staffId taxProfiles")
      .lean();

    if (!user) {
      console.log("❌ TAX YTD → User not found", employeeIdRaw);
      return res.status(404).json({ message: "User not found" });
    }

    console.log("✅ TAX YTD → User matched", {
      userId: user.userId,
      employeeCode: user.employeeCode,
      staffId: user.staffId,
    });

    const profile =
      (user.taxProfiles || []).find((p) => Number(p.taxYear) === year) || null;

    const { allowanceTotal } = calcAllowanceFromProfile(profile);

    const taxableYTD = Math.max(0, incomeYTD - allowanceTotal - (ssoYTD + pvdYTD));
    const taxDueYTD = calcProgressiveTax(taxableYTD);

    const withheldThisMonth = Math.max(0, taxDueYTD - taxPaidYTD);

    return res.json({
      taxYear: year,
      employeeId: employeeIdRaw,
      taxableYTD,
      taxDueYTD,
      taxPaidYTD,
      withheldThisMonth,
    });
  } catch (err) {
    console.error("calcTaxYTDInternal error:", err);
    return res.status(500).json({ message: "Server error" });
  }
};
