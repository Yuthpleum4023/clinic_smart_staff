// ==================================================
// schemas/Employee.js
// PURPOSE: Employee Master Data (Payroll-ready)
// + ✅ clinicId for multi-clinic scoping
// + ✅ idempotent-safe unique index for userId + clinicId
// + ✅ ready for internal ensure employee flow
// ==================================================

const mongoose = require("mongoose");

const EmployeeSchema = new mongoose.Schema(
  {
    // ✅ IMPORTANT (multi-clinic):
    // ใช้ clinicId จาก invite / auth / token ตอนสร้าง
    // เพื่อกันข้อมูลข้ามคลินิก
    clinicId: {
      type: String,
      required: true,
      index: true,
      trim: true,
      default: "",
    },

    // ✅ ผูกกับ user_service / auth_user_service
    userId: {
      type: String,
      required: true,
      index: true,
      trim: true,
      default: "",
    },

    fullName: {
      type: String,
      required: true,
      trim: true,
    },

    employmentType: {
      type: String,
      enum: ["fullTime", "partTime"],
      required: true,
      default: "fullTime",
    },

    // ---- PAY RATE ----
    monthlySalary: { type: Number, default: 0 }, // full-time
    hourlyRate: { type: Number, default: 0 }, // part-time

    // ---- WORK POLICY (override ได้รายคน) ----
    hoursPerDay: { type: Number, default: 8 },
    workingDaysPerMonth: { type: Number, default: 26 },

    // ---- OT POLICY ----
    otMultiplierNormal: { type: Number, default: 1.5 },
    otMultiplierHoliday: { type: Number, default: 2.0 },

    // ---- STATUS ----
    active: { type: Boolean, default: true },

    // ✅ useful for debugging / provisioning source
    provisionedFrom: {
      type: String,
      default: "manual",
      trim: true,
    },
  },
  { timestamps: true }
);

// --------------------------------------------------
// Indexes
// --------------------------------------------------

// ✅ query helper
EmployeeSchema.index({ clinicId: 1, active: 1, fullName: 1 });

// ✅ critical: prevent duplicate employee for same user in same clinic
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