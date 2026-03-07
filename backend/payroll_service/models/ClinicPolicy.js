// backend/payroll_service/models/ClinicPolicy.js
const mongoose = require("mongoose");

const OT_RULES = ["AFTER_DAILY_HOURS", "AFTER_SHIFT_END", "AFTER_CLOCK_TIME"];
const ROUNDING = ["NONE", "15MIN", "30MIN", "HOUR"];

const FeatureFlagsSchema = new mongoose.Schema(
  {
    manualAttendance: { type: Boolean, default: true },
    fingerprintAttendance: { type: Boolean, default: true },
    autoOtCalculation: { type: Boolean, default: true },
    otApprovalWorkflow: { type: Boolean, default: true },
    attendanceApproval: { type: Boolean, default: true },
    payrollLock: { type: Boolean, default: true },
    policyHumanReadable: { type: Boolean, default: true },
  },
  { _id: false }
);

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

    // ✅ OT rule
    otRule: { type: String, enum: OT_RULES, default: "AFTER_CLOCK_TIME" },

    // for AFTER_DAILY_HOURS
    regularHoursPerDay: { type: Number, default: 8 },

    // 🔹 LEGACY single clock time (fallback)
    otClockTime: { type: String, default: "18:00" },

    // ✅ Separate OT clock time by employment type (legacy-compatible)
    fullTimeOtClockTime: { type: String, default: "18:00" },
    partTimeOtClockTime: { type: String, default: "18:00" },

    // ✅ NEW: OT window (ใช้จริงตาม policy ปัจจุบัน)
    otWindowStart: { type: String, default: "18:00" },
    otWindowEnd: { type: String, default: "21:00" },

    // OT starts after shift end by N minutes
    otStartAfterMinutes: { type: Number, default: 0 },

    // rounding
    otRounding: { type: String, enum: ROUNDING, default: "15MIN" },

    // multipliers
    otMultiplier: { type: Number, default: 1.5 },
    holidayMultiplier: { type: Number, default: 2.0 },
    weekendAllDayOT: { type: Boolean, default: false },

    // ✅ NEW: core attendance / OT policy
    employeeOnlyOt: { type: Boolean, default: true },
    requireOtApproval: { type: Boolean, default: true },
    realTimeAttendanceOnly: { type: Boolean, default: true },
    manualAttendanceRequireApproval: { type: Boolean, default: true },
    manualReasonRequired: { type: Boolean, default: true },
    lockAfterPayrollClose: { type: Boolean, default: true },

    // ✅ NEW: approval roles
    attendanceApprovalRoles: {
      type: [String],
      default: ["clinic_admin"],
    },
    otApprovalRoles: {
      type: [String],
      default: ["clinic_admin"],
    },

    // ✅ NEW: feature flags
    features: {
      type: FeatureFlagsSchema,
      default: () => ({
        manualAttendance: true,
        fingerprintAttendance: true,
        autoOtCalculation: true,
        otApprovalWorkflow: true,
        attendanceApproval: true,
        payrollLock: true,
        policyHumanReadable: true,
      }),
    },

    // versioning
    version: { type: Number, default: 1 },
    updatedBy: { type: String, default: "" }, // userId admin
  },
  { timestamps: true }
);

module.exports = mongoose.model("ClinicPolicy", ClinicPolicySchema);