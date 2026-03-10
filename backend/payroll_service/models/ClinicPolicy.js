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

    // ======================================================
    // Attendance security
    // ======================================================
    requireBiometric: { type: Boolean, default: true },
    requireLocation: { type: Boolean, default: false },
    geoRadiusMeters: { type: Number, default: 200 },

    // ======================================================
    // Attendance late / early / cutoff rules
    // ======================================================
    graceLateMinutes: { type: Number, default: 10 },

    // เวลาตัดรอบของ workDate นั้น ๆ เช่น workDate 2026-03-10 cutoff 03:00
    // จะหมายถึง check-out ปกติได้ถึง 2026-03-11 03:00
    cutoffTime: { type: String, default: "03:00" },

    // กันกด check-out เร็วเกินไป เช่น 1 นาทีแรก
    minMinutesBeforeCheckout: { type: Number, default: 1 },

    // ถ้ามี open session จากวันก่อน -> ห้าม check-in ใหม่
    blockNewCheckInIfPreviousOpen: { type: Boolean, default: true },

    // ถ้าลืม check-out จนเกิน cutoff -> ต้องไป manual only
    forgotCheckoutManualOnly: { type: Boolean, default: true },

    // เข้างานก่อนเวลา ต้องมีเหตุผล/ไป manual flow
    requireReasonForEarlyCheckIn: { type: Boolean, default: true },

    // ออกก่อนเวลา ต้องมีเหตุผลก่อนจึงจะ checkout ได้
    requireReasonForEarlyCheckOut: { type: Boolean, default: true },

    // เผื่อ tolerance สำหรับ left early เช่น 0, 5, 10 นาที
    leaveEarlyToleranceMinutes: { type: Number, default: 0 },

    // ======================================================
    // OT rule
    // ======================================================
    otRule: { type: String, enum: OT_RULES, default: "AFTER_CLOCK_TIME" },

    // for AFTER_DAILY_HOURS
    regularHoursPerDay: { type: Number, default: 8 },

    // LEGACY single clock time (fallback)
    otClockTime: { type: String, default: "18:00" },

    // Separate OT clock time by employment type (legacy-compatible)
    fullTimeOtClockTime: { type: String, default: "18:00" },
    partTimeOtClockTime: { type: String, default: "18:00" },

    // OT window
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

    // ======================================================
    // Core attendance / OT policy
    // ======================================================
    employeeOnlyOt: { type: Boolean, default: true },
    requireOtApproval: { type: Boolean, default: true },
    realTimeAttendanceOnly: { type: Boolean, default: true },
    manualAttendanceRequireApproval: { type: Boolean, default: true },
    manualReasonRequired: { type: Boolean, default: true },
    lockAfterPayrollClose: { type: Boolean, default: true },

    // ======================================================
    // Approval roles
    // ======================================================
    attendanceApprovalRoles: {
      type: [String],
      default: ["clinic_admin"],
    },
    otApprovalRoles: {
      type: [String],
      default: ["clinic_admin"],
    },

    // ======================================================
    // Feature flags
    // ======================================================
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

    // ======================================================
    // Versioning / audit
    // ======================================================
    version: { type: Number, default: 1 },
    updatedBy: { type: String, default: "" }, // userId admin
  },
  { timestamps: true }
);

// useful indexes
ClinicPolicySchema.index({ clinicId: 1 }, { unique: true, name: "uniq_clinic_policy" });

module.exports = mongoose.model("ClinicPolicy", ClinicPolicySchema);