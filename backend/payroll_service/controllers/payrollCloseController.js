const axios = require("axios");
const PayrollClose = require("../models/PayrollClose");
const TaxYTD = require("../models/TaxYTD");

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
function safeStr(v) {
  return String(v || "").trim();
}
function baseUrlNoSlash(url) {
  return safeStr(url).replace(/\/$/, "");
}
async function postJson(url, body, headers) {
  return axios.post(url, body, {
    headers,
    timeout: 15000,
    validateStatus: () => true,
  });
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

  console.log("🔥 AUTH_INTERNAL CALL", {
    userId,
    taxYear,
    body,
  });

  const headers = {
    "Content-Type": "application/json",
    "x-internal-key": internalKey,
  };

  let lastErr = null;

  for (const url of candidates) {
    try {
      console.log("➡️ AUTH_INTERNAL POST", url);
      const res = await postJson(url, body, headers);

      console.log("⬅️ AUTH_INTERNAL RESP", {
        status: res.status,
        data: res.data,
      });

      if (res.status === 200) return res.data;

      lastErr = new Error(
        `AUTH_INTERNAL not 200: ${res.status} ${JSON.stringify(res.data)}`
      );
    } catch (e) {
      console.log("❌ AUTH_INTERNAL EXCEPTION", e.message);
      lastErr = e;
    }
  }

  throw lastErr || new Error("AUTH_INTERNAL call failed");
}

// ================= CLOSE MONTH =================
exports.closeMonth = async (req, res) => {
  try {
    const {
      clinicId,
      employeeId,
      month,
      grossBase = 0,
      otPay = 0,
      bonus = 0,
      otherAllowance = 0,
      otherDeduction = 0,
      ssoEmployeeMonthly = 0,
      pvdEmployeeMonthly = 0,
    } = req.body || {};

    if (!clinicId || !employeeId || !month) {
      return res
        .status(400)
        .json({ message: "clinicId, employeeId, month is required" });
    }

    // ✅ SUPERMAN FIX 🔥
    const userId = safeStr(req.user?.userId);

    if (!userId) {
      return res.status(401).json({ message: "Missing userId in token" });
    }

    console.log("🔥 CLOSE MONTH", {
      clinicId,
      employeeId,
      userId,
      month,
    });

    const existed = await PayrollClose.findOne({
      employeeId,
      month,
    }).lean();

    if (existed) {
      return res.status(409).json({ message: "Month already closed" });
    }

    const taxYear = monthToTaxYear(month);

    const grossMonthly = computeGrossMonthly({
      grossBase,
      otPay,
      bonus,
      otherAllowance,
      otherDeduction,
    });

    const ssoM = clamp(clampMin0(ssoEmployeeMonthly), 0, 750);
    const pvdM = clampMin0(pvdEmployeeMonthly);

    let ytd = await TaxYTD.findOne({ employeeId, taxYear });

    if (!ytd) {
      ytd = await TaxYTD.create({
        employeeId,
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

    const taxCalc = await calcWithheldByYTDFromAuth({
      userId, // ✅ FIX เด็ดขาด
      taxYear,
      incomeYTD: incomeYTD_after,
      ssoYTD: ssoYTD_after,
      pvdYTD: pvdYTD_after,
      taxPaidYTD: clampMin0(ytd.taxPaidYTD),
    });

    const withheldTaxMonthly = clampMin0(taxCalc?.withheldThisMonth);

    const netPay = Math.max(
      0,
      grossMonthly - withheldTaxMonthly - ssoM - pvdM
    );

    const payrollClose = await PayrollClose.create({
      clinicId,
      employeeId,
      month,
      grossMonthly,
      withheldTaxMonthly,
      netPay,
      locked: true,
      closedBy: userId,
    });

    ytd.incomeYTD = incomeYTD_after;
    ytd.ssoYTD = ssoYTD_after;
    ytd.pvdYTD = pvdYTD_after;
    ytd.taxPaidYTD += withheldTaxMonthly;

    await ytd.save();

    return res.json({ ok: true, payrollClose, ytd, taxCalc });
  } catch (err) {
    console.error("closeMonth error:", err);
    return res.status(500).json({
      message: "closeMonth failed",
      error: err.message,
    });
  }
};

exports.getClosedMonthsByEmployee = async (req, res) => {
  try {
    const { employeeId } = req.params;

    const rows = await PayrollClose.find({ employeeId })
      .sort({ month: -1 })
      .lean();

    return res.json({ ok: true, rows });
  } catch (err) {
    return res.status(500).json({
      message: "getClosedMonthsByEmployee failed",
      error: err.message,
    });
  }
};
