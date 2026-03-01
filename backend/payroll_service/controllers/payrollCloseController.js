// backend/payroll_service/controllers/payrollCloseController.js
//
// ✅ FULL FILE — Payroll Close Controller (OT Approved included)
// - ✅ employeeId in this system = staffId (ฟันธงให้ชัด)
// - ✅ Pull approved OT summary by (clinicId + monthKey + staffId)
// - ✅ If client sends baseHourly (optional) and otPay=0 => compute otPay from approvedWeightedHours
// - ✅ Still calls AUTH internal by userId (ถูกต้อง เพราะภาษีผูก userId)
// - ✅ Keep old fields + add OT snapshot fields to PayrollClose
//

const axios = require("axios");
const PayrollClose = require("../models/PayrollClose");
const TaxYTD = require("../models/TaxYTD");
const Overtime = require("../models/Overtime"); // ✅ NEW

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
function computeGrossMonthly({ grossBase, otPay, bonus, otherAllowance, otherDeduction }) {
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

// ================= OT helpers =================
// ✅ sum APPROVED OT of month (employeeId = staffId)
// - approvedMinutes = sum(minutes)
// - approvedWeightedHours = sum( (minutes/60) * multiplier )
//   -> if client sends baseHourly, backend can compute otPay = approvedWeightedHours * baseHourly
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

  const q = {
    clinicId: cId,
    monthKey: mKey,
    status: "approved",
    staffId, // ✅ FIX: no OR userId (กัน OT ข้ามคน)
  };

  const rows = await Overtime.find(q)
    .select({
      workDate: 1,
      minutes: 1,
      multiplier: 1,
      status: 1,
      source: 1,
      note: 1,
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

// ================= auth internal call =================
async function calcWithheldByYTDFromAuth({ userId, taxYear, incomeYTD, ssoYTD, pvdYTD, taxPaidYTD }) {
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

  console.log("🔥 AUTH_INTERNAL CALL", { userId, taxYear, body });

  const headers = {
    "Content-Type": "application/json",
    "x-internal-key": internalKey,
  };

  let lastErr = null;

  for (const url of candidates) {
    try {
      console.log("➡️ AUTH_INTERNAL POST", url);
      const res = await postJson(url, body, headers);

      console.log("⬅️ AUTH_INTERNAL RESP", { status: res.status, data: res.data });

      if (res.status === 200) return res.data;

      lastErr = new Error(`AUTH_INTERNAL not 200: ${res.status} ${JSON.stringify(res.data)}`);
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
      employeeId, // ✅ employeeId = staffId
      month, // yyyy-MM
      grossBase = 0,

      // ✅ client may send OT pay; backend will also compute summary from approved OT
      otPay = 0,

      bonus = 0,
      otherAllowance = 0,
      otherDeduction = 0,
      ssoEmployeeMonthly = 0,
      pvdEmployeeMonthly = 0,

      // ✅ OPTIONAL: if client provides baseHourly, backend can compute OT pay from approvedWeightedHours
      baseHourly = null,
    } = req.body || {};

    if (!clinicId || !employeeId || !month) {
      return res.status(400).json({ message: "clinicId, employeeId, month is required" });
    }

    // ✅ For tax calc we still need userId (auth service uses userId)
    const userId = safeStr(req.user?.userId);
    if (!userId) return res.status(401).json({ message: "Missing userId in token" });

    console.log("🔥 CLOSE MONTH", { clinicId, employeeId, userId, month });

    const existed = await PayrollClose.findOne({ employeeId, month }).lean();
    if (existed) return res.status(409).json({ message: "Month already closed" });

    // =========================
    // ✅ Pull approved OT summary of that month (employeeId = staffId)
    // =========================
    const otSummary = await getApprovedOtSummaryForMonth({
      clinicId,
      monthKey: safeStr(month),
      employeeId: safeStr(employeeId),
    });

    // If client didn't provide otPay (or provided 0), we can compute OT pay ONLY IF baseHourly is provided.
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
      userId,
      taxYear,
      incomeYTD: incomeYTD_after,
      ssoYTD: ssoYTD_after,
      pvdYTD: pvdYTD_after,
      taxPaidYTD: clampMin0(ytd.taxPaidYTD),
    });

    const withheldTaxMonthly = clampMin0(taxCalc?.withheldThisMonth);

    const netPay = Math.max(0, grossMonthly - withheldTaxMonthly - ssoM - pvdM);

    // ✅ Keep old fields, store OT snapshot fields too
    const payrollClose = await PayrollClose.create({
      clinicId,
      employeeId,
      month,

      // results
      grossMonthly,
      withheldTaxMonthly,
      netPay,

      // components (keep)
      grossBase: clampMin0(grossBase),
      otPay: otPayFinal,
      bonus: clampMin0(bonus),
      otherAllowance: clampMin0(otherAllowance),
      otherDeduction: clampMin0(otherDeduction),

      // statutory
      ssoEmployeeMonthly: ssoM,
      pvdEmployeeMonthly: pvdM,

      // ✅ OT snapshot (NEW fields in model)
      otApprovedMinutes: Math.max(0, Math.floor(Number(otSummary.approvedMinutes || 0))),
      otApprovedWeightedHours: clampMin0(otSummary.approvedWeightedHours),
      otApprovedCount: Math.max(0, Math.floor(Number(otSummary.count || 0))),

      locked: true,
      closedBy: userId,
    });

    // update ytd
    ytd.incomeYTD = incomeYTD_after;
    ytd.ssoYTD = ssoYTD_after;
    ytd.pvdYTD = pvdYTD_after;
    ytd.taxPaidYTD += withheldTaxMonthly;
    await ytd.save();

    return res.json({
      ok: true,
      payrollClose,
      ytd,
      taxCalc,
      otSummary: {
        monthKey: otSummary.monthKey,
        approvedMinutes: otSummary.approvedMinutes,
        approvedWeightedHours: otSummary.approvedWeightedHours,
        count: otSummary.count,
        records: otSummary.records, // optional debug
      },
    });
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