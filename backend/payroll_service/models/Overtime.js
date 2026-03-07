// backend/payroll_service/models/Overtime.js
const mongoose = require("mongoose");

const OT_STATUS = ["pending", "approved", "rejected", "locked"];
const OT_SOURCE = ["attendance", "manual", "manual_user"];
const PRINCIPAL_TYPE = ["staff", "user"];

function isYmd(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(v || "").trim());
}

function toMonthKey(workDate) {
  const s = String(workDate || "").trim();
  return isYmd(s) ? s.slice(0, 7) : "";
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

    // ✅ NEW: approved minutes (payroll will use this)
    approvedMinutes: { type: Number, default: 0 },

    multiplier: { type: Number, default: 1.5 },

    status: { type: String, enum: OT_STATUS, default: "pending", index: true },

    source: { type: String, enum: OT_SOURCE, default: "attendance", index: true },

    attendanceSessionId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "AttendanceSession",
      default: null,
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

OvertimeSchema.index({ clinicId: 1, principalId: 1, monthKey: 1, status: 1 });

OvertimeSchema.index({ clinicId: 1, monthKey: 1, status: 1 });

OvertimeSchema.index({ clinicId: 1, staffId: 1, monthKey: 1, status: 1 });

OvertimeSchema.index({ attendanceSessionId: 1 }, { unique: true, sparse: true });

// -------------------- Hooks --------------------

OvertimeSchema.pre("validate", function (next) {
  if (!this.monthKey) {
    this.monthKey = toMonthKey(this.workDate);
  }

  // backward compatibility
  if (!this.principalId) {
    const sid = String(this.staffId || "").trim();
    const uid = String(this.userId || "").trim();

    this.principalId = sid || uid || this.principalId;
    this.principalType = sid ? "staff" : "user";
  }

  next();
});

module.exports = mongoose.model("Overtime", OvertimeSchema);