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
 * ✅ ATTENDANCE RULE (UPDATED FOR MULTI-CLINIC HELPERS)
 * - 1 principal มี open session ได้พร้อมกันแค่ 1 อันทั้งระบบ
 * - 1 principal / 1 clinic / 1 workDate มี main session ได้ 1 อัน
 * - scan แรก = check-in
 * - scan ถัดมา (session open) = check-out
 * - ถ้าปิดวันแล้ว ห้ามเปิด session ใหม่เองใน clinic/date เดิม
 * - ถ้าผิด flow / เลย cut-off / ลืม check-out -> ไป manual request flow
 *
 * ✅ NEW
 * - schedule snapshot fields
 * - early leave / abnormal flags
 * - reasonCode / reasonText
 * - policy snapshot เพื่อให้คำนวณย้อนหลังได้แม้ admin เปลี่ยน policy ภายหลัง
 * - manual request fields สำหรับ approve/reject โดยคลินิก
 *
 * ✅ SECURITY EXTENSIONS
 * - suspiciousFlags
 * - riskScore
 * - securityMeta
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
     * - ""              : ไม่มี manual request
     * - check_in        : ขอเช็คอินย้อนหลัง
     * - check_out       : ขอเช็คเอาท์ย้อนหลัง
     * - edit_both       : ขอแก้ทั้งเวลาเข้า/เวลาออก
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
    // Security / Anti-cheat
    // ======================================================
    suspiciousFlags: {
      type: [String],
      default: [],
      index: true,
    },

    riskScore: {
      type: Number,
      default: 0,
      index: true,
    },

    securityMeta: {
      inDistanceMeters: { type: Number, default: null },
      outDistanceMeters: { type: Number, default: null },

      inLocationSource: { type: String, default: "" },
      outLocationSource: { type: String, default: "" },

      inMocked: { type: Boolean, default: false },
      outMocked: { type: Boolean, default: false },
    },

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

/**
 * ✅ RULE หลัก (ราย clinic/day):
 * 1 principal / 1 clinic / 1 workDate / 1 main session only
 *
 * main session statuses:
 * - open
 * - closed
 * - pending_manual
 *
 * cancelled ไม่นับเป็น main session
 *
 * หมายเหตุ:
 * index นี้จะกันไม่ให้มี session หลักมากกว่า 1 อันต่อวันใน clinic เดียว
 * เช่น:
 * - open แล้วสร้าง closed ซ้ำใน clinic/date เดิมไม่ได้
 * - closed แล้วกลับมาเปิดใหม่ใน clinic/date เดิมไม่ได้
 * - pending_manual ซ้ำอีกอันใน clinic/date เดิมไม่ได้
 */
AttendanceSessionSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1 },
  {
    unique: true,
    partialFilterExpression: {
      status: { $in: ["open", "closed", "pending_manual"] },
    },
    name: "uniq_main_session_per_principal_per_clinic_per_day",
  }
);

/**
 * ✅ NEW:
 * 1 principal มี open session ได้พร้อมกันแค่ 1 อันทั้งระบบ
 * ไม่ว่าจะเป็นคลินิกไหน
 *
 * สำคัญมากสำหรับ helper ที่ทำหลายคลินิก
 * เพื่อกัน race condition / request ซ้ำ / check-in พร้อมกันหลายที่
 */
AttendanceSessionSchema.index(
  { principalId: 1, status: 1 },
  {
    unique: true,
    partialFilterExpression: { status: "open" },
    name: "uniq_global_open_session_per_principal",
  }
);

// ✅ เผื่อ query หา open session เร็วใน clinic/day
AttendanceSessionSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, status: 1 },
  {
    partialFilterExpression: { status: "open" },
    name: "idx_open_session_per_day",
  }
);

// ✅ เผื่อ query หา pending manual เร็ว
AttendanceSessionSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1, status: 1 },
  {
    partialFilterExpression: { status: "pending_manual" },
    name: "idx_pending_manual_per_day",
  }
);

// ✅ query open session ระดับ principal เร็ว
AttendanceSessionSchema.index(
  { principalId: 1, status: 1, checkInAt: -1 },
  {
    partialFilterExpression: { status: "open" },
    name: "idx_principal_open_session_desc",
  }
);

// ✅ 1 principal/day timeline query
AttendanceSessionSchema.index(
  { clinicId: 1, principalId: 1, workDate: 1 },
  { name: "idx_principal_day" }
);

// ✅ staffId based queries (employee reports / legacy screens)
AttendanceSessionSchema.index(
  { clinicId: 1, staffId: 1, workDate: 1, status: 1 },
  { name: "idx_staff_day_status" }
);
AttendanceSessionSchema.index(
  { staffId: 1, checkInAt: -1 },
  { name: "idx_staff_checkin_desc" }
);

// ✅ principal timeline queries
AttendanceSessionSchema.index(
  { principalId: 1, checkInAt: -1 },
  { name: "idx_principal_checkin_desc" }
);

// clinic/day
AttendanceSessionSchema.index(
  { clinicId: 1, workDate: -1 },
  { name: "idx_clinic_workdate_desc" }
);

// approval / admin queue
AttendanceSessionSchema.index(
  { clinicId: 1, approvalStatus: 1, workDate: -1 },
  { name: "idx_clinic_approval_queue" }
);

// manual request queue
AttendanceSessionSchema.index(
  { clinicId: 1, manualRequestType: 1, approvalStatus: 1, workDate: -1 },
  { name: "idx_clinic_manual_queue" }
);

// source filters
AttendanceSessionSchema.index(
  { clinicId: 1, source: 1, workDate: -1 },
  { name: "idx_clinic_source_workdate" }
);

// abnormal / early leave admin review
AttendanceSessionSchema.index(
  { clinicId: 1, abnormal: 1, workDate: -1 },
  { name: "idx_clinic_abnormal_workdate" }
);
AttendanceSessionSchema.index(
  { clinicId: 1, leftEarly: 1, workDate: -1 },
  { name: "idx_clinic_left_early_workdate" }
);

// security / anti-cheat review
AttendanceSessionSchema.index(
  { clinicId: 1, riskScore: -1, workDate: -1 },
  { name: "idx_clinic_riskscore_workdate" }
);
AttendanceSessionSchema.index(
  { clinicId: 1, suspiciousFlags: 1, workDate: -1 },
  { name: "idx_clinic_suspiciousflags_workdate" }
);

// reason filters
AttendanceSessionSchema.index(
  { clinicId: 1, reasonCode: 1, workDate: -1 },
  { name: "idx_clinic_reason_workdate" }
);
AttendanceSessionSchema.index(
  { clinicId: 1, abnormalReasonCode: 1, workDate: -1 },
  { name: "idx_clinic_abnormal_reason_workdate" }
);
AttendanceSessionSchema.index(
  { clinicId: 1, requestReasonCode: 1, workDate: -1 },
  { name: "idx_clinic_request_reason_workdate" }
);

// payroll lock filters
AttendanceSessionSchema.index(
  { clinicId: 1, lockedByPayroll: 1, workDate: -1 },
  { name: "idx_clinic_payroll_lock_workdate" }
);
AttendanceSessionSchema.index(
  { clinicId: 1, lockedMonth: 1, principalId: 1 },
  { name: "idx_clinic_locked_month_principal" }
);

module.exports = mongoose.model("AttendanceSession", AttendanceSessionSchema);