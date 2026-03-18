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

    // identity
    principalId: { type: String, required: true, index: true },
    principalType: {
      type: String,
      enum: PRINCIPAL_TYPE,
      default: "staff",
      index: true,
    },

    staffId: { type: String, default: "", index: true },
    userId: { type: String, default: "", index: true },

    workDate: { type: String, required: true, index: true },
    monthKey: { type: String, required: true, index: true },

    // requested minutes
    minutes: { type: Number, required: true, min: 0, default: 0 },

    // payroll should use this
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

    attendanceSessionId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "AttendanceSession",
      default: null,
      index: true,
    },

    // admin actions
    approvedBy: { type: String, default: "" },
    approvedAt: { type: Date, default: null },

    rejectedBy: { type: String, default: "" },
    rejectedAt: { type: Date, default: null },
    rejectReason: { type: String, default: "" },

    // manual create
    createdBy: { type: String, default: "" },

    note: { type: String, default: "" },

    // payroll lock
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

// auto OT from attendance: 1 attendance session -> 1 OT record only
OvertimeSchema.index(
  { attendanceSessionId: 1 },
  { unique: true, sparse: true, name: "uniq_ot_attendance_session" }
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
    // normalize simple strings
    this.clinicId = s(this.clinicId);
    this.principalId = s(this.principalId);
    this.staffId = s(this.staffId);
    this.userId = s(this.userId);
    this.workDate = s(this.workDate);
    this.monthKey = s(this.monthKey);
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

    // backward compatibility
    if (!this.principalId) {
      const sid = s(this.staffId);
      const uid = s(this.userId);
      this.principalId = sid || uid || this.principalId;
    }

    if (!this.principalType || !PRINCIPAL_TYPE.includes(this.principalType)) {
      this.principalType = s(this.staffId) ? "staff" : "user";
    }

    // normalize numbers
    this.minutes = clampNonNegativeNumber(this.minutes, 0);
    this.approvedMinutes = clampNonNegativeNumber(this.approvedMinutes, 0);
    this.multiplier = clampNonNegativeNumber(this.multiplier, 1.5) || 1.5;

    // approvedMinutes ห้ามเกิน minutes
    if (this.approvedMinutes > this.minutes) {
      this.approvedMinutes = this.minutes;
    }

    next();
  } catch (err) {
    next(err);
  }
});

module.exports = mongoose.model("Overtime", OvertimeSchema);