// backend/payroll_service/models/AttendanceSession.js
const mongoose = require("mongoose");

/**
 * ✅ Durable Attendance Identity
 * - staffId      : ใช้เมื่อเป็น employee (มี stf_...)
 * - userId       : เก็บ userId เสมอ (usr_...)
 * - principalId  : ตัวตนหลักสำหรับ attendance (staffId ถ้ามี ไม่งั้นใช้ userId)
 * - principalType: "staff" | "user"
 *
 * ✅ helper (ไม่มี staffId) ลงเวลาได้ โดยไม่ต้องยัด usr_ ไปใน staffId
 *
 * ✅ V1 ATTENDANCE RULE
 * - 1 principal ต่อ 1 workDate ควรมี 1 session หลัก
 * - scan แรก = check-in
 * - scan ถัดมา (session open) = check-out
 * - ถ้าปิดวันแล้ว ห้ามเปิด session ใหม่เอง
 * - ถ้าผิด flow / เลย cut-off / ลืม check-out -> ไป manual request flow
 *
 * ✅ NEW
 * - schedule snapshot fields
 * - early leave / abnormal flags
 * - reasonCode / reasonText
 * - policy snapshot เพื่อให้คำนวณย้อนหลังได้แม้ admin เปลี่ยน policy ภายหลัง
 * - manual request fields สำหรับ approve/reject โดยคลินิก
 */

const AttendanceSessionSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },

    // ======================================================
    // Identity
    // ======================================================
    principalId: { type: String, required: true, index: true }, // staffId || userId
    principalType: {
      type: String,
      enum: ["staff", "user"],
      default: "staff",
      index: true,
    },

    staffId: { type: String, default: "", index: true },
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

    // ======================================================
    // Attendance timestamps (actual)
    // ======================================================
    checkInAt: { type: Date, required: true },
    checkOutAt: { type: Date, default: null },

    /**
     * status meaning
     * - open           : session เปิดอยู่
     * - closed         : session ปิดแล้ว
     * - cancelled      : ยกเลิก
     * - pending_manual : มีคำขอ manual แก้ไข/ปิดเวลา รออนุมัติ
     */
    status: {
      type: String,
      enum: ["open", "closed", "cancelled", "pending_manual"],
      default: "open",
      index: true,
    },

    // ======================================================
    // Method / biometric meta
    // ======================================================
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

    // ======================================================
    // Source / manual / approval
    // ======================================================
    source: {
      type: String,
      enum: ["fingerprint", "manual"],
      default: "fingerprint",
      index: true,
    },

    /**
     * เหตุผลระดับ session เช่น เข้างานก่อนเวลา / ออกก่อนเวลา
     */
    reasonCode: { type: String, default: "", index: true },
    reasonText: { type: String, default: "" },

    // legacy/manual text (ยังเก็บไว้เพื่อ backward compatibility)
    manualReason: { type: String, default: "" },

    /**
     * approvalStatus
     * - none      : ไม่ต้องอนุมัติ
     * - pending   : รออนุมัติ
     * - approved  : อนุมัติแล้ว
     * - rejected  : ปฏิเสธแล้ว
     */
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

    // ======================================================
    // Manual request flow
    // ======================================================
    /**
     * manualRequestType
     * - ""            : ไม่มี manual request
     * - check_in      : ขอเช็คอินย้อนหลัง
     * - check_out     : ขอเช็คเอาท์ย้อนหลัง
     * - edit_both     : ขอแก้ทั้งเวลาเข้า/เวลาออก
     * - forgot_checkout : ลืมเช็คเอาท์
     */
    manualRequestType: {
      type: String,
      enum: ["", "check_in", "check_out", "edit_both", "forgot_checkout"],
      default: "",
      index: true,
    },

    requestedCheckInAt: { type: Date, default: null },
    requestedCheckOutAt: { type: Date, default: null },

    requestedBy: { type: String, default: "", index: true },
    requestedAt: { type: Date, default: null },

    requestReasonCode: { type: String, default: "", index: true },
    requestReasonText: { type: String, default: "" },

    manualLocked: { type: Boolean, default: false, index: true },

    // ======================================================
    // Location (optional)
    // ======================================================
    inLat: { type: Number, default: null },
    inLng: { type: Number, default: null },
    outLat: { type: Number, default: null },
    outLng: { type: Number, default: null },

    // ======================================================
    // Schedule / policy snapshot of that day
    // IMPORTANT:
    // เก็บ snapshot ตอน check-in เพื่อกัน policy เปลี่ยนย้อนหลัง
    // ======================================================
    scheduledStart: { type: String, default: "" }, // "08:00"
    scheduledEnd: { type: String, default: "" }, // "17:00"

    normalMinutesBeforeOt: { type: Number, default: 0 }, // เช่น 480
    otWindowStart: { type: String, default: "" }, // "17:00"
    otWindowEnd: { type: String, default: "" }, // "21:00"
    cutoffTime: { type: String, default: "" }, // "03:00"

    graceMinutes: { type: Number, default: 0 },
    leaveEarlyToleranceMinutes: { type: Number, default: 0 },

    // ======================================================
    // Computed / reporting
    // ======================================================
    workedMinutes: { type: Number, default: 0 },
    lateMinutes: { type: Number, default: 0 },
    otMinutes: { type: Number, default: 0 },

    leftEarly: { type: Boolean, default: false, index: true },
    leftEarlyMinutes: { type: Number, default: 0 },

    abnormal: { type: Boolean, default: false, index: true },
    abnormalReasonCode: { type: String, default: "", index: true },
    abnormalReasonText: { type: String, default: "" },

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

// ✅ prevent duplicate OPEN sessions per principal per day
AttendanceSessionSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, status: 1 },
  {
    partialFilterExpression: { status: "open" },
    unique: true,
  }
);

// ✅ prevent duplicate PENDING_MANUAL session state per principal per day
AttendanceSessionSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, status: 1 },
  {
    partialFilterExpression: { status: "pending_manual" },
  }
);

// ✅ 1 principal/day timeline query
AttendanceSessionSchema.index({ clinicId: 1, principalId: 1, workDate: 1 });

// ✅ staffId based queries (employee reports / legacy screens)
AttendanceSessionSchema.index({
  clinicId: 1,
  staffId: 1,
  workDate: 1,
  status: 1,
});
AttendanceSessionSchema.index({ staffId: 1, checkInAt: -1 });

// ✅ principal timeline queries
AttendanceSessionSchema.index({ principalId: 1, checkInAt: -1 });

// clinic/day
AttendanceSessionSchema.index({ clinicId: 1, workDate: -1 });

// approval / admin queue
AttendanceSessionSchema.index({
  clinicId: 1,
  approvalStatus: 1,
  workDate: -1,
});

// manual request queue
AttendanceSessionSchema.index({
  clinicId: 1,
  manualRequestType: 1,
  approvalStatus: 1,
  workDate: -1,
});

// source filters
AttendanceSessionSchema.index({ clinicId: 1, source: 1, workDate: -1 });

// abnormal / early leave admin review
AttendanceSessionSchema.index({ clinicId: 1, abnormal: 1, workDate: -1 });
AttendanceSessionSchema.index({ clinicId: 1, leftEarly: 1, workDate: -1 });

// reason filters
AttendanceSessionSchema.index({ clinicId: 1, reasonCode: 1, workDate: -1 });
AttendanceSessionSchema.index({
  clinicId: 1,
  abnormalReasonCode: 1,
  workDate: -1,
});
AttendanceSessionSchema.index({
  clinicId: 1,
  requestReasonCode: 1,
  workDate: -1,
});

// payroll lock filters
AttendanceSessionSchema.index({
  clinicId: 1,
  lockedByPayroll: 1,
  workDate: -1,
});
AttendanceSessionSchema.index({
  clinicId: 1,
  lockedMonth: 1,
  principalId: 1,
});

module.exports = mongoose.model("AttendanceSession", AttendanceSessionSchema);