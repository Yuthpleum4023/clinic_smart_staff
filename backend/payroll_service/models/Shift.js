// payroll_service/models/Shift.js
const mongoose = require("mongoose");

const ShiftSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },
    staffId: { type: String, required: true, index: true },

    date: { type: String, required: true },  // yyyy-MM-dd
    start: { type: String, required: true }, // HH:mm
    end: { type: String, required: true },   // HH:mm

    status: {
      type: String,
      enum: ["scheduled", "completed", "late", "cancelled", "no_show"],
      default: "scheduled",
      index: true,
    },

    minutesLate: { type: Number, default: 0 },

    hourlyRate: { type: Number, default: 0 }, // บาท/ชั่วโมง
    note: { type: String, default: "" },
  },
  { timestamps: true }
);

ShiftSchema.index({ clinicId: 1, staffId: 1, date: -1 });

module.exports = mongoose.model("Shift", ShiftSchema);
