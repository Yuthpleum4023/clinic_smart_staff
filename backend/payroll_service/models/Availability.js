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
    end: { type: String, required: true },   // "18:00"
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
  },
  { timestamps: true }
);

// Index ช่วย query "คลินิกดูรายการ open"
AvailabilitySchema.index({ status: 1, date: 1, start: 1 });
AvailabilitySchema.index({ staffId: 1, date: 1 });

module.exports = mongoose.model("Availability", AvailabilitySchema);