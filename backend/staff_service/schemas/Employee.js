// ==================================================
// schemas/Employee.js
// PURPOSE: Employee Master Data (Payroll-ready)
// ==================================================

const mongoose = require("mongoose");

const EmployeeSchema = new mongoose.Schema(
  {
    // ถ้าผูกกับ user_service
    userId: { type: String },

    fullName: { type: String, required: true },

    employmentType: {
      type: String,
      enum: ["fullTime", "partTime"],
      required: true,
    },

    // ---- PAY RATE ----
    monthlySalary: { type: Number }, // full-time
    hourlyRate: { type: Number }, // part-time

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

module.exports = mongoose.model("Employee", EmployeeSchema);
