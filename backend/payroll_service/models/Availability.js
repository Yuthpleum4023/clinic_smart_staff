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
    // ✅ link to Shift created from booking (SAFE)
    // =========================================================
    // ✅ IMPORTANT: ไม่ใส่ index:true ตรงนี้ เพื่อกัน duplicate กับ schema.index()
    shiftId: { type: String, default: "" },

    // note/rate ตอนคลินิกจอง (optional)
    bookedNote: { type: String, default: "" },
    bookedHourlyRate: { type: Number, default: 0 },

    // =========================================================
    // ✅ NEW: clinic clear (ให้คลินิก “เคลียร์” รายการที่จองแล้วออกจากหน้าคลินิก)
    // - ไม่ทำให้กลับไป open (กันคนอื่นเห็นซ้ำ)
    // - แค่ซ่อนออกจาก /availabilities/booked
    // =========================================================
    clinicClearedAt: { type: Date, default: null, index: true },
  },
  { timestamps: true }
);

// Index ช่วย query "คลินิกดูรายการ open"
AvailabilitySchema.index({ status: 1, date: 1, start: 1 });
AvailabilitySchema.index({ staffId: 1, date: 1 });

// query รายการที่ถูกจองแล้ว + เรียงตามวัน/เวลา
AvailabilitySchema.index({ bookedByClinicId: 1, date: 1, start: 1 });

// ✅ NEW: query booked ของคลินิกที่ “ยังไม่เคลียร์”
AvailabilitySchema.index({
  bookedByClinicId: 1,
  status: 1,
  clinicClearedAt: 1,
  date: 1,
  start: 1,
});

// trace จาก shift กลับไป availability
AvailabilitySchema.index({ shiftId: 1 });

module.exports = mongoose.model("Availability", AvailabilitySchema);