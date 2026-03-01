// backend/payroll_service/models/ClinicPolicy.js
const mongoose = require("mongoose");

const OT_RULES = ["AFTER_DAILY_HOURS", "AFTER_SHIFT_END", "AFTER_CLOCK_TIME"];
const ROUNDING = ["NONE", "15MIN", "30MIN", "HOUR"];

const ClinicPolicySchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, unique: true, index: true },

    timezone: { type: String, default: "Asia/Bangkok" },

    // Attendance security
    requireBiometric: { type: Boolean, default: true },
    requireLocation: { type: Boolean, default: false },
    geoRadiusMeters: { type: Number, default: 200 },

    // Late rule
    graceLateMinutes: { type: Number, default: 10 },

    // ✅ OT rule (default changed to AFTER_CLOCK_TIME)
    otRule: { type: String, enum: OT_RULES, default: "AFTER_CLOCK_TIME" },

    // for AFTER_DAILY_HOURS (ยังคงไว้ เผื่ออนาคต)
    regularHoursPerDay: { type: Number, default: 8 },

    // 🔹 LEGACY single clock time (fallback)
    otClockTime: { type: String, default: "18:00" },

    // ✅ NEW: Separate OT clock time by employment type
    fullTimeOtClockTime: { type: String, default: "18:00" },
    partTimeOtClockTime: { type: String, default: "18:00" },

    // OT starts after shift end by N minutes
    otStartAfterMinutes: { type: Number, default: 0 },

    // rounding
    otRounding: { type: String, enum: ROUNDING, default: "15MIN" },

    // multipliers
    otMultiplier: { type: Number, default: 1.5 },
    holidayMultiplier: { type: Number, default: 2.0 },
    weekendAllDayOT: { type: Boolean, default: false },

    // versioning
    version: { type: Number, default: 1 },
    updatedBy: { type: String, default: "" }, // userId admin
  },
  { timestamps: true }
);

module.exports = mongoose.model("ClinicPolicy", ClinicPolicySchema);