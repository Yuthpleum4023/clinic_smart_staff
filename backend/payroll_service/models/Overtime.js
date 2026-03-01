// backend/payroll_service/models/Overtime.js
const mongoose = require("mongoose");

const OT_STATUS = ["pending", "approved", "rejected", "locked"];
const OT_SOURCE = ["attendance", "manual"];

function isYmd(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(v || "").trim());
}

function toMonthKey(workDate) {
  const s = String(workDate || "").trim(); // yyyy-MM-dd
  return isYmd(s) ? s.slice(0, 7) : "";
}

const OvertimeSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },

    // ✅ primary employee reference in payroll_service
    staffId: { type: String, required: true, index: true },

    // optional (for fetching employee master / audit)
    userId: { type: String, default: "", index: true },

    // business date (yyyy-MM-dd)
    workDate: { type: String, required: true, index: true },

    // month key (yyyy-MM) for faster queries (auto derived if missing)
    monthKey: { type: String, required: true, index: true },

    // OT duration
    minutes: { type: Number, required: true, min: 0, default: 0 },

    // for pay calculation / audit (optional)
    multiplier: { type: Number, default: 1.5 },

    // status lifecycle
    status: { type: String, enum: OT_STATUS, default: "pending", index: true },

    // source
    source: { type: String, enum: OT_SOURCE, default: "attendance", index: true },

    // link back to attendance session (only when source=attendance)
    attendanceSessionId: { type: mongoose.Schema.Types.ObjectId, ref: "AttendanceSession", default: null },

    // admin actions
    approvedBy: { type: String, default: "" }, // admin userId
    approvedAt: { type: Date, default: null },

    rejectedBy: { type: String, default: "" }, // admin userId
    rejectedAt: { type: Date, default: null },
    rejectReason: { type: String, default: "" },

    // edits / notes
    note: { type: String, default: "" },

    // lock info (locked by payroll close)
    lockedBy: { type: String, default: "" }, // admin userId
    lockedAt: { type: Date, default: null },
    lockedMonth: { type: String, default: "" }, // yyyy-MM
  },
  { timestamps: true }
);

// helpful compound indexes
OvertimeSchema.index({ clinicId: 1, staffId: 1, monthKey: 1, status: 1 });
OvertimeSchema.index({ clinicId: 1, monthKey: 1, status: 1 });

// ✅ prevent duplicate auto OT per attendance session (sparse allows many nulls)
OvertimeSchema.index({ attendanceSessionId: 1 }, { unique: true, sparse: true });

// keep monthKey consistent
OvertimeSchema.pre("validate", function (next) {
  if (!this.monthKey) this.monthKey = toMonthKey(this.workDate);
  next();
});

module.exports = mongoose.model("Overtime", OvertimeSchema);