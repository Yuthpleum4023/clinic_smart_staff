const mongoose = require("mongoose");

const AttendanceEventSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },
    staffId: { type: String, required: true, index: true },
    shiftId: { type: String, default: "", index: true },

    // ✅ ให้ตรงกับ controller: cancelled_early
    status: {
      type: String,
      enum: ["completed", "late", "no_show", "cancelled_early"],
      required: true,
      index: true,
    },

    minutesLate: { type: Number, default: 0 },

    occurredAt: { type: Date, required: true, index: true },
  },
  { timestamps: true }
);

AttendanceEventSchema.index({ staffId: 1, occurredAt: -1 });

module.exports = mongoose.model("AttendanceEvent", AttendanceEventSchema);
