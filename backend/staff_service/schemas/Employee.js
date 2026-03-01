// ==================================================
// schemas/Employee.js
// PURPOSE: Employee Master Data (Payroll-ready)
// + ✅ clinicId for multi-clinic scoping
// ==================================================

const mongoose = require("mongoose");

const EmployeeSchema = new mongoose.Schema(
  {
    // ✅ IMPORTANT (multi-clinic):
    // ใช้ clinicId จาก token (admin) ตอนสร้าง/อัปเดต เพื่อกันข้อมูลข้ามคลินิก
    clinicId: { type: String, index: true, default: "" },

    // ถ้าผูกกับ user_service
    userId: { type: String, index: true, default: "" },

    fullName: { type: String, required: true },

    employmentType: {
      type: String,
      enum: ["fullTime", "partTime"],
      required: true,
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

    active: { type: Boolean, default: true },
  },
  { timestamps: true }
);

// ✅ Helpful indexes (optional but good)
EmployeeSchema.index({ clinicId: 1, active: 1, fullName: 1 });
EmployeeSchema.index({ clinicId: 1, userId: 1 });

module.exports = mongoose.model("Employee", EmployeeSchema);