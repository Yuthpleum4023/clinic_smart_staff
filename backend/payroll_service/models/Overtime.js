// backend/payroll_service/models/Overtime.js
const mongoose = require("mongoose");

const OT_STATUS = ["pending", "approved", "rejected", "locked"];
const OT_SOURCE = ["attendance", "manual", "manual_user"];
const PRINCIPAL_TYPE = ["staff", "user"];

function s(v) {
  return String(v || "").trim();
}

function isYmd(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(v || "").trim());
}

function toMonthKey(workDate) {
  const x = s(workDate);
  return isYmd(x) ? x.slice(0, 7) : "";
}

function clampNonNegativeNumber(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, n);
}

const OvertimeSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },

    // --------------------
    // Identity
    // --------------------
    principalId: { type: String, required: true, index: true },
    principalType: {
      type: String,
      enum: PRINCIPAL_TYPE,
      default: "staff",
      index: true,
    },

    staffId: { type: String, default: "", index: true },
    userId: { type: String, default: "", index: true },

    // --------------------
    // Work date
    // --------------------
    workDate: { type: String, required: true, index: true }, // yyyy-MM-dd
    monthKey: { type: String, required: true, index: true }, // yyyy-MM

    // --------------------
    // Time snapshot
    // Manual OT/admin OT should keep these for UI display.
    // Attendance OT can also fill them when available.
    // --------------------
    start: { type: String, default: "" }, // HH:mm
    end: { type: String, default: "" }, // HH:mm
    startTime: { type: String, default: "" }, // compatibility
    endTime: { type: String, default: "" }, // compatibility

    // --------------------
    // Minutes / payroll
    // --------------------
    minutes: { type: Number, required: true, min: 0, default: 0 },

    // Payroll must use approvedMinutes for approved/locked rows.
    approvedMinutes: { type: Number, default: 0, min: 0 },

    multiplier: { type: Number, default: 1.5, min: 0 },

    status: {
      type: String,
      enum: OT_STATUS,
      default: "pending",
      index: true,
    },

    source: {
      type: String,
      enum: OT_SOURCE,
      default: "attendance",
      index: true,
    },

    /**
     * IMPORTANT PRODUCTION FIX:
     *
     * Do NOT default this to null.
     *
     * Old version used:
     *   default: null + unique sparse index
     *
     * That can make many manual OT rows collide on attendanceSessionId=null,
     * causing POST /overtime/manual -> 409 even when workDate is new.
     *
     * Manual OT should simply omit attendanceSessionId.
     */
    attendanceSessionId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "AttendanceSession",
      default: undefined,
    },

    // --------------------
    // Admin actions
    // --------------------
    approvedBy: { type: String, default: "" },
    approvedAt: { type: Date, default: null },

    rejectedBy: { type: String, default: "" },
    rejectedAt: { type: Date, default: null },
    rejectReason: { type: String, default: "" },

    // Manual create
    createdBy: { type: String, default: "" },

    note: { type: String, default: "" },

    // --------------------
    // Payroll lock
    // --------------------
    lockedBy: { type: String, default: "" },
    lockedAt: { type: Date, default: null },
    lockedMonth: { type: String, default: "" },
  },
  { timestamps: true }
);

// -------------------- Indexes --------------------

// principal/month queries
OvertimeSchema.index(
  { clinicId: 1, principalId: 1, monthKey: 1, status: 1 },
  { name: "idx_ot_clinic_principal_month_status" }
);

OvertimeSchema.index(
  { clinicId: 1, monthKey: 1, status: 1 },
  { name: "idx_ot_clinic_month_status" }
);

OvertimeSchema.index(
  { clinicId: 1, staffId: 1, monthKey: 1, status: 1 },
  { name: "idx_ot_clinic_staff_month_status" }
);

OvertimeSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, status: 1 },
  { name: "idx_ot_clinic_principal_workdate_status" }
);

OvertimeSchema.index(
  { clinicId: 1, source: 1, workDate: 1, principalId: 1 },
  { name: "idx_ot_clinic_source_workdate_principal" }
);

/**
 * Auto OT from attendance:
 * 1 attendance session -> 1 OT record only.
 *
 * IMPORTANT:
 * Unique only when attendanceSessionId is a real ObjectId.
 * Manual OT rows do not have attendanceSessionId and must never collide.
 */
OvertimeSchema.index(
  { attendanceSessionId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      attendanceSessionId: { $type: "objectId" },
    },
    name: "uniq_ot_attendance_session",
  }
);

/**
 * manual_user:
 * 1 principal / 1 clinic / 1 workDate
 * ให้มี request ที่ active ได้แค่อันเดียว
 *
 * rejected ไม่รวม เพื่อให้ส่งใหม่ได้หลังโดน reject
 */
OvertimeSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, source: 1 },
  {
    unique: true,
    partialFilterExpression: {
      source: "manual_user",
      status: { $in: ["pending", "approved", "locked"] },
    },
    name: "uniq_manual_user_ot_per_principal_per_day",
  }
);

/**
 * admin manual OT:
 * 1 principal / 1 clinic / 1 workDate
 * ให้มี manual OT active ได้แค่อันเดียว
 *
 * rejected ไม่รวม เพื่อให้สร้างใหม่ได้ถ้าจำเป็น
 *
 * Controller ฝั่ง createManual ควร update รายการเดิมแทนตอบ 409
 * เพื่อให้ production flow ใช้งานง่ายเมื่อ admin แก้เวลา OT วันเดิม
 */
OvertimeSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, source: 1 },
  {
    unique: true,
    partialFilterExpression: {
      source: "manual",
      status: { $in: ["pending", "approved", "locked"] },
    },
    name: "uniq_manual_admin_ot_per_principal_per_day",
  }
);

// -------------------- Hooks --------------------

OvertimeSchema.pre("validate", function (next) {
  try {
    // Normalize simple strings
    this.clinicId = s(this.clinicId);
    this.principalId = s(this.principalId);
    this.staffId = s(this.staffId);
    this.userId = s(this.userId);

    this.workDate = s(this.workDate);
    this.monthKey = s(this.monthKey);

    this.start = s(this.start);
    this.end = s(this.end);
    this.startTime = s(this.startTime);
    this.endTime = s(this.endTime);

    this.note = s(this.note);
    this.createdBy = s(this.createdBy);

    this.approvedBy = s(this.approvedBy);
    this.rejectedBy = s(this.rejectedBy);
    this.rejectReason = s(this.rejectReason);

    this.lockedBy = s(this.lockedBy);
    this.lockedMonth = s(this.lockedMonth);

    if (!this.monthKey) {
      this.monthKey = toMonthKey(this.workDate);
    }

    // Backward compatibility
    if (!this.principalId) {
      const sid = s(this.staffId);
      const uid = s(this.userId);
      this.principalId = sid || uid || this.principalId;
    }

    if (!this.principalType || !PRINCIPAL_TYPE.includes(this.principalType)) {
      this.principalType = s(this.staffId) ? "staff" : "user";
    }

    // Mirror start/end for old/new UI compatibility
    if (!this.start && this.startTime) this.start = this.startTime;
    if (!this.end && this.endTime) this.end = this.endTime;
    if (!this.startTime && this.start) this.startTime = this.start;
    if (!this.endTime && this.end) this.endTime = this.end;

    // Normalize numbers
    this.minutes = clampNonNegativeNumber(this.minutes, 0);
    this.approvedMinutes = clampNonNegativeNumber(this.approvedMinutes, 0);
    this.multiplier = clampNonNegativeNumber(this.multiplier, 1.5) || 1.5;

    // approvedMinutes ห้ามเกิน minutes
    if (this.approvedMinutes > this.minutes) {
      this.approvedMinutes = this.minutes;
    }

    // Manual OT must not store null attendanceSessionId
    if (this.source !== "attendance" && !this.attendanceSessionId) {
      this.attendanceSessionId = undefined;
    }

    // If approved/locked and approvedMinutes still 0, use minutes.
    // This protects admin manual OT when client/backend sends status=approved.
    if (
      (this.status === "approved" || this.status === "locked") &&
      this.minutes > 0 &&
      this.approvedMinutes <= 0
    ) {
      this.approvedMinutes = this.minutes;
    }

    next();
  } catch (err) {
    next(err);
  }
});

module.exports = mongoose.model("Overtime", OvertimeSchema);