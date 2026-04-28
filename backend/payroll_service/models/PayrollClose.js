// backend/payroll_service/models/PayrollClose.js
//
// ✅ PRODUCTION — PayrollClose model
//
// ✅ PURPOSE:
// - เก็บผลปิดงวดเงินเดือนที่ backend คำนวณแล้ว
// - employeeId = staffId
// - clinicId + employeeId + month ต้อง unique
// - รองรับ backend-only payroll calculator
// - รองรับ preview / close / recalculate flow
//
// ✅ IMPORTANT:
// - Raw accounting components เก็บเป็นตัวเลขจริงที่ backend ใช้คำนวณ
// - Display snapshot fields ใช้ render หน้า detail / payslip / PDF โดยไม่คำนวณซ้ำ
// - snapshot ใช้ Mixed เพื่อเก็บ audit/debug/calculation metadata จาก backend ได้ครบ
//
// ✅ WHY snapshot is Mixed:
// controller ใหม่บันทึก audit fields จำนวนมาก เช่น:
// - payrollCalculator
// - grossBaseSource
// - employmentTypeResolved
// - hourlyRateResolved
// - regularWorkHours / regularWorkMinutes
// - bonusUsed / otherAllowanceUsed / leaveDeduction
// - ignoredClientInputs
// - sso policy / tax YTD / OT rate
//
// ถ้ากำหนด snapshot เป็น schema แคบ ๆ Mongoose strict mode จะทิ้ง field ใหม่
//

const mongoose = require("mongoose");

const { Schema } = mongoose;

const PayrollCloseSchema = new Schema(
  {
    // =============================
    // Identity
    // =============================
    clinicId: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },

    // ✅ employeeId = staffId จาก staff_service
    employeeId: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },

    // yyyy-MM เช่น 2026-04
    month: {
      type: String,
      required: true,
      trim: true,
      index: true,
      match: /^\d{4}-\d{2}$/,
    },

    // =============================
    // Tax mode
    // =============================
    taxMode: {
      type: String,
      enum: ["WITHHOLDING", "NO_WITHHOLDING"],
      default: "WITHHOLDING",
      index: true,
    },

    // =============================
    // Raw / accounting components
    // Backend calculated / accepted inputs
    // =============================
    grossBase: {
      type: Number,
      default: 0,
      min: 0,
    },

    otPay: {
      type: Number,
      default: 0,
      min: 0,
    },

    bonus: {
      type: Number,
      default: 0,
      min: 0,
    },

    otherAllowance: {
      type: Number,
      default: 0,
      min: 0,
    },

    // ใช้เป็นหักลา/ขาด/รายการหักหลัก
    otherDeduction: {
      type: Number,
      default: 0,
      min: 0,
    },

    // =============================
    // Statutory deductions
    // =============================
    ssoEmployeeMonthly: {
      type: Number,
      default: 0,
      min: 0,
    },

    pvdEmployeeMonthly: {
      type: Number,
      default: 0,
      min: 0,
    },

    // =============================
    // Final results
    // =============================
    grossMonthly: {
      type: Number,
      default: 0,
      min: 0,
    },

    withheldTaxMonthly: {
      type: Number,
      default: 0,
      min: 0,
    },

    netPay: {
      type: Number,
      default: 0,
      min: 0,
    },

    // =============================
    // OT snapshot from approved overtime
    // =============================
    otApprovedMinutes: {
      type: Number,
      default: 0,
      min: 0,
    },

    otApprovedWeightedHours: {
      type: Number,
      default: 0,
      min: 0,
    },

    otApprovedCount: {
      type: Number,
      default: 0,
      min: 0,
    },

    // =============================
    // Display snapshot fields
    // ใช้ render ตรง ๆ ใน detail / preview / PDF
    // ห้ามเอาไปคำนวณซ้ำใน Flutter
    // =============================
    displayNetBeforeOt: {
      type: Number,
      default: 0,
      min: 0,
    },

    displayLeaveDeduction: {
      type: Number,
      default: 0,
      min: 0,
    },

    displayOtHours: {
      type: Number,
      default: 0,
      min: 0,
    },

    displayOtAmount: {
      type: Number,
      default: 0,
      min: 0,
    },

    displayGrossBeforeTax: {
      type: Number,
      default: 0,
      min: 0,
    },

    displayTaxAmount: {
      type: Number,
      default: 0,
      min: 0,
    },

    displaySsoAmount: {
      type: Number,
      default: 0,
      min: 0,
    },

    displayPvdAmount: {
      type: Number,
      default: 0,
      min: 0,
    },

    displayNetPay: {
      type: Number,
      default: 0,
      min: 0,
    },

    displaySalaryBaseForSso: {
      type: Number,
      default: 0,
      min: 0,
    },

    // =============================
    // Lock & audit
    // =============================
    locked: {
      type: Boolean,
      default: true,
      index: true,
    },

    closedAt: {
      type: Date,
      default: Date.now,
      index: true,
    },

    closedBy: {
      type: String,
      default: "",
      trim: true,
      index: true,
    },

    // =============================
    // Calculation snapshot / audit
    // ✅ Mixed เพื่อเก็บ audit fields จาก backend-only calculator ได้ครบ
    // =============================
    snapshot: {
      type: Schema.Types.Mixed,
      default: {},
    },
  },
  {
    timestamps: true,
    minimize: false,
  }
);

// ✅ กันปิดงวดซ้ำในคลินิกเดียวกัน
PayrollCloseSchema.index(
  { clinicId: 1, employeeId: 1, month: 1 },
  { unique: true }
);

// ✅ query เร็วขึ้นสำหรับ list เดือนของพนักงาน
PayrollCloseSchema.index({ clinicId: 1, employeeId: 1, closedAt: -1 });

// ✅ query เร็วขึ้นสำหรับรายงานทั้งคลินิกตามเดือน
PayrollCloseSchema.index({ clinicId: 1, month: -1 });

module.exports = mongoose.model("PayrollClose", PayrollCloseSchema);