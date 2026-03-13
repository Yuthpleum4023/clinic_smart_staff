const mongoose = require("mongoose");

const StaffGlobalScoreSchema = new mongoose.Schema(
  {
    staffId: {
      type: String,
      required: true,
      unique: true,
      index: true,
      trim: true,
    },

    globalTrustScore: {
      type: Number,
      default: 80,
      min: 0,
      max: 100,
    },

    clinicCount: {
      type: Number,
      default: 0,
      min: 0,
    },

    totalShifts: {
      type: Number,
      default: 0,
      min: 0,
    },

    completed: {
      type: Number,
      default: 0,
      min: 0,
    },

    late: {
      type: Number,
      default: 0,
      min: 0,
    },

    noShow: {
      type: Number,
      default: 0,
      min: 0,
    },

    cancelledEarly: {
      type: Number,
      default: 0,
      min: 0,
    },

    level: {
      type: String,
      default: "unknown",
      enum: ["excellent", "good", "normal", "risk", "unknown"],
      index: true,
    },

    levelLabel: {
      type: String,
      default: "ยังไม่มีข้อมูล",
    },

    levelUpdatedAt: {
      type: Date,
      default: null,
    },

    flags: {
      type: [String],
      default: [],
    },

    badges: {
      type: [String],
      default: [],
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model("StaffGlobalScore", StaffGlobalScoreSchema);