// ==================================================
// schemas/Employee.js
// PURPOSE: Employee Master Data (Payroll-ready)
//
// ✅ PRODUCTION FULL FILE
// - clinicId for multi-clinic scoping
// - userId / linkedUserId for employee ↔ user account
// - payroll-ready fields: monthlySalary, hourlyRate, bonus, absentDays
// - position / employeeCode persisted in backend
// - idempotent-safe unique index for clinicId + userId
// - allows unlinked employee records safely
// ==================================================

const mongoose = require("mongoose");

function toSafeNumber(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

const EmployeeSchema = new mongoose.Schema(
  {
    // --------------------------------------------------
    // Multi-clinic scope
    // --------------------------------------------------
    clinicId: {
      type: String,
      required: true,
      index: true,
      trim: true,
      default: "",
    },

    // --------------------------------------------------
    // User account link
    // --------------------------------------------------
    // ✅ userId ไม่บังคับ เพื่อรองรับพนักงานที่ยังไม่ได้ผูกบัญชี
    // ✅ unique index ด้านล่างจะทำงานเฉพาะกรณี userId ไม่ว่าง
    userId: {
      type: String,
      required: false,
      index: true,
      trim: true,
      default: "",
    },

    // ✅ alias/compatibility สำหรับ Flutter/payroll resolver
    linkedUserId: {
      type: String,
      required: false,
      index: true,
      trim: true,
      default: "",
    },

    // --------------------------------------------------
    // Identity
    // --------------------------------------------------
    employeeCode: {
      type: String,
      trim: true,
      default: "",
    },

    fullName: {
      type: String,
      required: true,
      trim: true,
    },

    position: {
      type: String,
      trim: true,
      default: "Staff",
    },

    // --------------------------------------------------
    // Employment type
    // --------------------------------------------------
    employmentType: {
      type: String,
      enum: ["fullTime", "partTime"],
      required: true,
      default: "fullTime",
      index: true,
    },

    // --------------------------------------------------
    // Pay rate
    // --------------------------------------------------
    monthlySalary: {
      type: Number,
      default: 0,
      min: 0,
    }, // full-time

    hourlyRate: {
      type: Number,
      default: 0,
      min: 0,
    }, // part-time

    // --------------------------------------------------
    // Payroll adjustment fields
    // --------------------------------------------------
    // ✅ ใช้กับ EmployeeDetail / PayrollClose input
    // ✅ backend payroll จะใช้ค่าเหล่านี้ได้ในอนาคตหรือใช้ Flutter ส่งเข้า close/recalculate
    bonus: {
      type: Number,
      default: 0,
      min: 0,
    },

    // ✅ จำนวนวันลา/ขาด สำหรับ full-time
    absentDays: {
      type: Number,
      default: 0,
      min: 0,
      max: 31,
    },

    // ✅ เผื่อใช้แยก commission/allowance ในอนาคต
    otherAllowance: {
      type: Number,
      default: 0,
      min: 0,
    },

    // ✅ เผื่อใช้หักอื่น ๆ นอกเหนือจาก absentDays
    otherDeduction: {
      type: Number,
      default: 0,
      min: 0,
    },

    // --------------------------------------------------
    // Work policy override per employee
    // --------------------------------------------------
    hoursPerDay: {
      type: Number,
      default: 8,
      min: 0,
    },

    workingDaysPerMonth: {
      type: Number,
      default: 26,
      min: 0,
    },

    // --------------------------------------------------
    // OT policy override per employee
    // --------------------------------------------------
    otMultiplierNormal: {
      type: Number,
      default: 1.5,
      min: 0,
    },

    otMultiplierHoliday: {
      type: Number,
      default: 2.0,
      min: 0,
    },

    // --------------------------------------------------
    // Status / audit
    // --------------------------------------------------
    active: {
      type: Boolean,
      default: true,
      index: true,
    },

    provisionedFrom: {
      type: String,
      default: "manual",
      trim: true,
    },
  },
  {
    timestamps: true,
    toJSON: { virtuals: true },
    toObject: { virtuals: true },
  }
);

// --------------------------------------------------
// Virtuals for Flutter compatibility
// --------------------------------------------------
EmployeeSchema.virtual("staffId").get(function getStaffId() {
  return String(this._id || "");
});

EmployeeSchema.virtual("baseSalary").get(function getBaseSalary() {
  return this.monthlySalary || 0;
});

EmployeeSchema.virtual("hourlyWage").get(function getHourlyWage() {
  return this.hourlyRate || 0;
});

// --------------------------------------------------
// Normalize before validate/save
// --------------------------------------------------
EmployeeSchema.pre("validate", function normalizeEmployee(next) {
  this.clinicId = String(this.clinicId || "").trim();
  this.userId = String(this.userId || "").trim();
  this.linkedUserId = String(this.linkedUserId || "").trim();
  this.fullName = String(this.fullName || "").trim();
  this.position = String(this.position || "Staff").trim();
  this.employeeCode = String(this.employeeCode || "").trim();

  // sync userId / linkedUserId
  if (!this.userId && this.linkedUserId) {
    this.userId = this.linkedUserId;
  }
  if (!this.linkedUserId && this.userId) {
    this.linkedUserId = this.userId;
  }

  this.monthlySalary = Math.max(0, toSafeNumber(this.monthlySalary, 0));
  this.hourlyRate = Math.max(0, toSafeNumber(this.hourlyRate, 0));
  this.bonus = Math.max(0, toSafeNumber(this.bonus, 0));
  this.absentDays = Math.max(
    0,
    Math.min(31, Math.floor(toSafeNumber(this.absentDays, 0)))
  );
  this.otherAllowance = Math.max(0, toSafeNumber(this.otherAllowance, 0));
  this.otherDeduction = Math.max(0, toSafeNumber(this.otherDeduction, 0));
  this.hoursPerDay = Math.max(0, toSafeNumber(this.hoursPerDay, 8));
  this.workingDaysPerMonth = Math.max(
    0,
    toSafeNumber(this.workingDaysPerMonth, 26)
  );
  this.otMultiplierNormal = Math.max(
    0,
    toSafeNumber(this.otMultiplierNormal, 1.5)
  );
  this.otMultiplierHoliday = Math.max(
    0,
    toSafeNumber(this.otMultiplierHoliday, 2.0)
  );

  // part-time ไม่ควรมี monthlySalary เป็นฐานหลัก
  if (this.employmentType === "partTime") {
    this.monthlySalary = 0;
    this.absentDays = 0;
  }

  // full-time ไม่ควรมี hourlyRate เป็นฐานหลัก
  if (this.employmentType === "fullTime") {
    this.hourlyRate = 0;
  }

  next();
});

// --------------------------------------------------
// Indexes
// --------------------------------------------------
EmployeeSchema.index({ clinicId: 1, active: 1, fullName: 1 });
EmployeeSchema.index({ clinicId: 1, employmentType: 1, active: 1 });
EmployeeSchema.index({ clinicId: 1, employeeCode: 1 });

// ✅ prevent duplicate employee for same user in same clinic
// ทำงานเฉพาะกรณี clinicId/userId ไม่ว่าง
EmployeeSchema.index(
  { clinicId: 1, userId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      clinicId: { $type: "string", $ne: "" },
      userId: { $type: "string", $ne: "" },
    },
  }
);

module.exports = mongoose.model("Employee", EmployeeSchema);