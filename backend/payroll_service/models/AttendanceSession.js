// backend/payroll_service/models/AttendanceSession.js
const mongoose = require("mongoose");

/**
 * ✅ Durable Attendance Identity
 * - staffId      : ใช้เมื่อเป็น employee (มี stf_...)
 * - userId       : เก็บ userId เสมอ (usr_...)
 * - principalId  : ตัวตนหลักสำหรับ attendance (staffId ถ้ามี ไม่งั้นใช้ userId)
 * - principalType: "staff" | "user"
 *
 * ✅ ทำให้ helper (ไม่มี staffId) ลงเวลาได้ โดยไม่ต้องยัด usr_ ไปใน staffId
 *
 * ✅ NEW:
 * - source / manualReason / approval fields
 * - รองรับ policy manual approval / audit trail ในอนาคต
 */

const AttendanceSessionSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },

    // ✅ identity ที่ใช้ query หลักสำหรับ attendance
    principalId: { type: String, required: true, index: true }, // staffId || userId
    principalType: {
      type: String,
      enum: ["staff", "user"],
      default: "staff",
      index: true,
    },

    // ✅ staffId แยกออกมา (อาจว่างได้สำหรับ helper marketplace)
    staffId: { type: String, default: "", index: true },

    // ✅ userId (usr_...)
    userId: { type: String, default: "", index: true },

    // optional link to shift
    shiftId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Shift",
      default: null,
      index: true,
    },

    // local business date (yyyy-MM-dd) for reporting
    workDate: { type: String, required: true, index: true },

    // timestamps (ISO/UTC)
    checkInAt: { type: Date, required: true },
    checkOutAt: { type: Date, default: null },

    status: {
      type: String,
      enum: ["open", "closed", "cancelled"],
      default: "open",
      index: true,
    },

    // method/meta
    checkInMethod: {
      type: String,
      enum: ["biometric", "manual"],
      default: "biometric",
    },
    checkOutMethod: {
      type: String,
      enum: ["biometric", "manual"],
      default: "biometric",
    },

    biometricVerifiedIn: { type: Boolean, default: false },
    biometricVerifiedOut: { type: Boolean, default: false },

    deviceId: { type: String, default: "" },

    // ✅ source/audit
    source: {
      type: String,
      enum: ["fingerprint", "manual"],
      default: "fingerprint",
      index: true,
    },
    manualReason: { type: String, default: "" },

    approvalStatus: {
      type: String,
      enum: ["none", "pending", "approved", "rejected"],
      default: "none",
      index: true,
    },
    approvedBy: { type: String, default: "" },
    approvedAt: { type: Date, default: null },
    approvalNote: { type: String, default: "" },

    rejectedBy: { type: String, default: "" },
    rejectedAt: { type: Date, default: null },
    rejectReason: { type: String, default: "" },

    // location (optional)
    inLat: { type: Number, default: null },
    inLng: { type: Number, default: null },
    outLat: { type: Number, default: null },
    outLng: { type: Number, default: null },

    // computed
    workedMinutes: { type: Number, default: 0 },
    lateMinutes: { type: Number, default: 0 },
    otMinutes: { type: Number, default: 0 },

    note: { type: String, default: "" },

    // payroll lock / audit
    lockedByPayroll: { type: Boolean, default: false, index: true },
    lockedMonth: { type: String, default: "", index: true },

    // versioning / debug
    policyVersion: { type: Number, default: 0 },
  },
  { timestamps: true }
);

// ======================================================
// Indexes
// ======================================================

// ✅ prevent duplicate open sessions per principal per day
AttendanceSessionSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, status: 1 },
  { partialFilterExpression: { status: "open" } }
);

// ✅ staffId based queries (employee reports / legacy screens)
AttendanceSessionSchema.index({ clinicId: 1, staffId: 1, workDate: 1, status: 1 });
AttendanceSessionSchema.index({ staffId: 1, checkInAt: -1 });

// ✅ principal timeline queries
AttendanceSessionSchema.index({ principalId: 1, checkInAt: -1 });

// clinic/day
AttendanceSessionSchema.index({ clinicId: 1, workDate: -1 });

// approval / admin queue
AttendanceSessionSchema.index({ clinicId: 1, approvalStatus: 1, workDate: -1 });

// source filters
AttendanceSessionSchema.index({ clinicId: 1, source: 1, workDate: -1 });

module.exports = mongoose.model("AttendanceSession", AttendanceSessionSchema);