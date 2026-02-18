// payroll_service/models/Shift.js
const mongoose = require("mongoose");

const ShiftSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },
    staffId: { type: String, required: true, index: true },

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
    // ✅ NEW — Clinic Navigation Data (ไม่กระทบของเดิม)
    // =========================================================

    // ใช้ default null เพื่อให้รู้ว่า "ยังไม่มีพิกัดจริง"
    clinicLat: { type: Number, default: null },
    clinicLng: { type: Number, default: null },

    clinicName: { type: String, default: "" },
    clinicPhone: { type: String, default: "" },
    clinicAddress: { type: String, default: "" },
  },
  { timestamps: true }
);

// เดิมของท่าน
ShiftSchema.index({ clinicId: 1, staffId: 1, date: -1 });

// ✅ เพิ่ม index ช่วย query งานของคลินิก/ผู้ช่วยไวขึ้น (ไม่กระทบของเดิม)
ShiftSchema.index({ clinicId: 1, date: -1, createdAt: -1 });
ShiftSchema.index({ staffId: 1, date: -1, createdAt: -1 });

module.exports = mongoose.model("Shift", ShiftSchema);
