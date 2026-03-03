// backend/payroll_service/models/Overtime.js
const mongoose = require("mongoose");

const OT_STATUS = ["pending", "approved", "rejected", "locked"];
const OT_SOURCE = ["attendance", "manual"];
const PRINCIPAL_TYPE = ["staff", "user"];

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

    // ✅ NEW: identity (รองรับ helper ไม่มี staffId)
    // - employee: principalId=staffId, principalType="staff"
    // - helper  : principalId=userId,  principalType="user"
    principalId: { type: String, required: true, index: true },
    principalType: {
      type: String,
      enum: PRINCIPAL_TYPE,
      default: "staff",
      index: true,
    },

    // ✅ staffId เก็บ "stf_..." จริงเท่านั้น (optional)
    staffId: { type: String, default: "", index: true },

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
    // ✅ IMPORTANT: อย่าใส่ index:true ที่ field นี้ เพราะเรามี unique+sparse index ด้านล่างอยู่แล้ว
    attendanceSessionId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "AttendanceSession",
      default: null,
    },

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

// -------------------- Indexes --------------------

// ✅ payroll main query (recommended) by principalId
OvertimeSchema.index({ clinicId: 1, principalId: 1, monthKey: 1, status: 1 });

// ✅ report query by month/status
OvertimeSchema.index({ clinicId: 1, monthKey: 1, status: 1 });

// ✅ optional: if clinic ยัง query ด้วย staffId เดิม (employee list)
OvertimeSchema.index({ clinicId: 1, staffId: 1, monthKey: 1, status: 1 });

// ✅ prevent duplicate auto OT per attendance session (sparse allows many nulls)
OvertimeSchema.index({ attendanceSessionId: 1 }, { unique: true, sparse: true });

// -------------------- Hooks --------------------

// keep monthKey consistent + backward compatibility guard (รวมเป็น hook เดียวกัน)
OvertimeSchema.pre("validate", function (next) {
  // monthKey
  if (!this.monthKey) this.monthKey = toMonthKey(this.workDate);

  // backward compatibility:
  // ถ้าเอกสารถูกสร้างจากของเก่า (มี staffId แต่ไม่มี principalId) -> เติม principalId ให้เอง
  if (!this.principalId) {
    const sid = String(this.staffId || "").trim();
    const uid = String(this.userId || "").trim();
    // priority: staffId > userId
    this.principalId = sid || uid || this.principalId;
    this.principalType = sid ? "staff" : "user";
  }

  next();
});

module.exports = mongoose.model("Overtime", OvertimeSchema);