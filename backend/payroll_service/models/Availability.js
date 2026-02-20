// models/Availability.js
const mongoose = require("mongoose");

const AvailabilitySchema = new mongoose.Schema(
  {
    // ผู้ช่วย/พนักงาน
    staffId: { type: String, required: true, index: true },
    userId: { type: String, default: "", index: true },

    // meta เผื่อโชว์ให้คลินิก (optional)
    fullName: { type: String, default: "" },
    phone: { type: String, default: "" },

    // ตารางว่าง
    date: { type: String, required: true, index: true }, // "YYYY-MM-DD"
    start: { type: String, required: true }, // "09:00"
    end: { type: String, required: true }, // "18:00"
    role: { type: String, default: "ผู้ช่วย" },
    note: { type: String, default: "" },

    status: {
      type: String,
      enum: ["open", "cancelled", "booked"],
      default: "open",
      index: true,
    },

    // ถ้าอนาคตคลินิกชวน/จอง จะเติมได้
    bookedByClinicId: { type: String, default: "", index: true },
    bookedAt: { type: Date, default: null },

    // =========================================================
    // ✅ NEW (SAFE) — link to Shift created from booking
    // =========================================================
    // shiftId = ObjectId ของ Shift ที่สร้างตอนจอง
    // ถ้าไม่สร้าง shift ก็ปล่อยว่างได้ (ไม่กระทบของเดิม)
    // ✅ IMPORTANT: ไม่ใส่ index:true ตรงนี้ เพื่อกัน duplicate กับ schema.index()
    shiftId: { type: String, default: "" },

    // เผื่อคลินิกใส่ note ตอนจอง (UI ส่งมา)
    bookedNote: { type: String, default: "" },

    // เผื่อเก็บเรทตอนจอง (ถ้าท่านอยากให้จองแล้วกำหนด hourlyRate ได้)
    bookedHourlyRate: { type: Number, default: 0 },
  },
  { timestamps: true }
);

// Index ช่วย query "คลินิกดูรายการ open"
AvailabilitySchema.index({ status: 1, date: 1, start: 1 });
AvailabilitySchema.index({ staffId: 1, date: 1 });

// ✅ query รายการที่ถูกจองแล้ว + เรียงตามวัน/เวลา
AvailabilitySchema.index({ bookedByClinicId: 1, date: 1, start: 1 });

// ✅ trace จาก shift กลับไป availability (สำคัญตอน debug)
AvailabilitySchema.index({ shiftId: 1 });

module.exports = mongoose.model("Availability", AvailabilitySchema);