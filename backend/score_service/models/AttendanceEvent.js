const mongoose = require("mongoose");

const AttendanceEventSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },
    staffId: { type: String, required: true, index: true },
    shiftId: { type: String, default: "", index: true },

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

AttendanceEventSchema.index({ clinicId: 1, staffId: 1, occurredAt: -1 });
AttendanceEventSchema.index({ clinicId: 1, status: 1, occurredAt: -1 });
AttendanceEventSchema.index({ staffId: 1, occurredAt: -1 });

// กัน event ซ้ำกรณีมี shiftId
AttendanceEventSchema.index(
  { clinicId: 1, staffId: 1, shiftId: 1, status: 1 },
  {
    unique: true,
    partialFilterExpression: {
      shiftId: { $type: "string", $ne: "" },
    },
  }
);

module.exports = mongoose.model("AttendanceEvent", AttendanceEventSchema);