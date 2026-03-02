// payroll_service/models/Shift.js
const mongoose = require("mongoose");

const ShiftSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },

    // ✅ เดิมของท่าน (ยัง required เพื่อไม่กระทบระบบฝั่ง employee/admin)
    staffId: { type: String, required: true, index: true },

    // ✅ NEW (ยั่งยืน): ผูก “งานของผู้ช่วย marketplace” กับ userId โดยตรง
    // - ช่วยแก้เคส token ไม่มี staffId
    // - optional เพื่อ backward compatible
    helperUserId: { type: String, default: "", index: true },

    date: { type: String, required: true }, // yyyy-MM-dd
    start: { type: String, required: true }, // HH:mm
    end: { type: String, required: true }, // HH:mm

    status: {
      type: String,
      enum: ["scheduled", "completed", "late", "cancelled", "no_show"],
      default: "scheduled",
      index: true,
    },

    minutesLate: { type: Number, default: 0 },

    hourlyRate: { type: Number, default: 0 }, // บาท/ชั่วโมง
    note: { type: String, default: "" },

    // =========================================================
    // ✅ Clinic Navigation Data (ไม่กระทบของเดิม)
    // =========================================================
    clinicLat: { type: Number, default: null },
    clinicLng: { type: Number, default: null },

    clinicName: { type: String, default: "" },
    clinicPhone: { type: String, default: "" },
    clinicAddress: { type: String, default: "" },
  },
  { timestamps: true }
);

// -------------------- Indexes --------------------

// เดิมของท่าน
ShiftSchema.index({ clinicId: 1, staffId: 1, date: -1 });

// เดิมของท่าน
ShiftSchema.index({ clinicId: 1, date: -1, createdAt: -1 });
ShiftSchema.index({ staffId: 1, date: -1, createdAt: -1 });

// ✅ NEW: index สำหรับ helperUserId (ช่วยให้ “งานของฉัน” เร็วและยั่งยืน)
ShiftSchema.index({ helperUserId: 1, date: -1, createdAt: -1 });
ShiftSchema.index({ clinicId: 1, helperUserId: 1, date: -1 });

module.exports = mongoose.model("Shift", ShiftSchema);