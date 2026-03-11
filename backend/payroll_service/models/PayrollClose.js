// backend/payroll_service/models/PayrollClose.js
//
// ✅ FULL FILE — PayrollClose model
// ✅ PATCH NEW:
// - เพิ่ม taxMode รองรับ 2 เส้นทาง:
//   1) WITHHOLDING
//   2) NO_WITHHOLDING
// - แก้ unique index ให้ผูก clinicId + employeeId + month
//
// ✅ KEEP:
// - employeeId = staffId
// - เก็บ components เดิมครบ
// - เก็บ OT snapshot fields
//

const mongoose = require("mongoose");

const PayrollCloseSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },
    employeeId: { type: String, required: true, index: true }, // ✅ staffId

    // "yyyy-MM" เช่น "2026-02"
    month: { type: String, required: true, index: true },

    // ✅ NEW: เส้นทางภาษี
    taxMode: {
      type: String,
      enum: ["WITHHOLDING", "NO_WITHHOLDING"],
      default: "WITHHOLDING",
      index: true,
    },

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

    // ✅ OT snapshot from approved overtime
    otApprovedMinutes: { type: Number, default: 0 },
    otApprovedWeightedHours: { type: Number, default: 0 },
    otApprovedCount: { type: Number, default: 0 },

    // lock & audit
    locked: { type: Boolean, default: true },
    closedAt: { type: Date, default: Date.now },
    closedBy: { type: String, default: "" },

    snapshot: {
      taxYear: { type: Number, default: 0 },
      allowanceTotalAnnual: { type: Number, default: 0 },
      incomeYTD_after: { type: Number, default: 0 },
      ssoYTD_after: { type: Number, default: 0 },
      pvdYTD_after: { type: Number, default: 0 },
      taxableYTD: { type: Number, default: 0 },
      taxDueYTD: { type: Number, default: 0 },
      taxPaidYTD_before: { type: Number, default: 0 },
      taxPaidYTD_after: { type: Number, default: 0 },
    },
  },
  { timestamps: true }
);

// ✅ กันปิดงวดซ้ำ "ในคลินิกเดียวกัน"
PayrollCloseSchema.index(
  { clinicId: 1, employeeId: 1, month: 1 },
  { unique: true }
);

module.exports = mongoose.model("PayrollClose", PayrollCloseSchema);