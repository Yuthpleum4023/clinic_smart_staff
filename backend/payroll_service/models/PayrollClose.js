// backend/payroll_service/models/PayrollClose.js
//
// ✅ FULL FILE — PayrollClose model (keep old fields + add OT snapshot fields)
// - ✅ employeeId = staffId
// - ✅ Keep components fields (grossBase, otPay, bonus, otherAllowance, otherDeduction)
// - ✅ Add OT snapshot fields so data doesn't disappear (strict schema)
//

const mongoose = require("mongoose");

const PayrollCloseSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },
    employeeId: { type: String, required: true, index: true }, // ✅ staffId

    // "yyyy-MM" เช่น "2026-02"
    month: { type: String, required: true, index: true },

    // components
    grossBase: { type: Number, default: 0 },
    otPay: { type: Number, default: 0 },
    bonus: { type: Number, default: 0 },
    otherAllowance: { type: Number, default: 0 },
    otherDeduction: { type: Number, default: 0 },

    // statutory (employee)
    ssoEmployeeMonthly: { type: Number, default: 0 },
    pvdEmployeeMonthly: { type: Number, default: 0 },

    // results
    grossMonthly: { type: Number, default: 0 },
    withheldTaxMonthly: { type: Number, default: 0 },
    netPay: { type: Number, default: 0 },

    // ✅ NEW: OT snapshot from approved overtime
    // - minutes: sum approved minutes
    // - weightedHours: sum((minutes/60) * multiplier)
    // - count: number of approved overtime records
    otApprovedMinutes: { type: Number, default: 0 },
    otApprovedWeightedHours: { type: Number, default: 0 },
    otApprovedCount: { type: Number, default: 0 },

    // lock & audit
    locked: { type: Boolean, default: true },
    closedAt: { type: Date, default: Date.now },
    closedBy: { type: String, default: "" },

    snapshot: {
      taxYear: Number,
      allowanceTotalAnnual: Number,
      incomeYTD_after: Number,
      ssoYTD_after: Number,
      pvdYTD_after: Number,
      taxableYTD: Number,
      taxDueYTD: Number,
      taxPaidYTD_before: Number,
      taxPaidYTD_after: Number,
    },
  },
  { timestamps: true }
);

// กันปิดงวดซ้ำ
PayrollCloseSchema.index({ employeeId: 1, month: 1 }, { unique: true });

module.exports = mongoose.model("PayrollClose", PayrollCloseSchema);