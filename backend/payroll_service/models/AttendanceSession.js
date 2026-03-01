// backend/payroll_service/models/AttendanceSession.js
const mongoose = require("mongoose");

const AttendanceSessionSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },
    staffId: { type: String, required: true, index: true },
    userId: { type: String, default: "", index: true },

    // optional link to shift
    shiftId: { type: mongoose.Schema.Types.ObjectId, ref: "Shift", default: null, index: true },

    // local business date (yyyy-MM-dd) for reporting
    workDate: { type: String, required: true, index: true },

    // timestamps (ISO/UTC)
    checkInAt: { type: Date, required: true },
    checkOutAt: { type: Date, default: null },

    status: { type: String, enum: ["open", "closed", "cancelled"], default: "open", index: true },

    // method/meta
    checkInMethod: { type: String, enum: ["biometric", "manual"], default: "biometric" },
    checkOutMethod: { type: String, enum: ["biometric", "manual"], default: "biometric" },

    biometricVerifiedIn: { type: Boolean, default: false },
    biometricVerifiedOut: { type: Boolean, default: false },

    deviceId: { type: String, default: "" },

    // location (optional)
    inLat: { type: Number, default: null },
    inLng: { type: Number, default: null },
    outLat: { type: Number, default: null },
    outLng: { type: Number, default: null },

    // computed
    workedMinutes: { type: Number, default: 0 },
    lateMinutes: { type: Number, default: 0 },
    otMinutes: { type: Number, default: 0 },

    note: { type: String, default: "" },

    // versioning / debug
    policyVersion: { type: Number, default: 0 },
  },
  { timestamps: true }
);

// prevent duplicate open sessions per staff per day
AttendanceSessionSchema.index(
  { clinicId: 1, staffId: 1, workDate: 1, status: 1 },
  { partialFilterExpression: { status: "open" } }
);

AttendanceSessionSchema.index({ staffId: 1, checkInAt: -1 });
AttendanceSessionSchema.index({ clinicId: 1, workDate: -1 });

module.exports = mongoose.model("AttendanceSession", AttendanceSessionSchema);