const mongoose = require("mongoose");

const TrustScoreSchema = new mongoose.Schema(
  {
    // =========================
    // IDENTIFIERS
    // =========================
    staffId: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },

    clinicId: {
      type: String,
      default: "global",
      trim: true,
      index: true,
    },

    // =========================
    // HELPER IDENTITY (NEW)
    // =========================
    userId: {
      type: String,
      default: "",
      trim: true,
      index: true,
    },

    principalId: {
      type: String,
      default: "",
      trim: true,
      index: true,
    },

    fullName: {
      type: String,
      default: "",
      trim: true,
    },

    name: {
      type: String,
      default: "",
      trim: true,
    },

    phone: {
      type: String,
      default: "",
      trim: true,
    },

    role: {
      type: String,
      default: "helper",
      trim: true,
      index: true,
    },

    // =========================
    // SCORE CORE
    // =========================
    trustScore: {
      type: Number,
      default: 80,
      min: 0,
      max: 100,
      index: true,
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

    // =========================
    // LEVEL
    // =========================
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

    // =========================
    // META
    // =========================
    lastNoShowAt: {
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

/**
 * IMPORTANT FOR SAAS
 * staff 1 คน สามารถมีคะแนนแยกหลาย clinic ได้
 */
TrustScoreSchema.index(
  { staffId: 1, clinicId: 1 },
  { unique: true }
);

/**
 * INDEXES FOR MARKETPLACE
 */
TrustScoreSchema.index({ userId: 1, updatedAt: -1 });
TrustScoreSchema.index({ principalId: 1, updatedAt: -1 });
TrustScoreSchema.index({ trustScore: -1, updatedAt: -1 });

module.exports = mongoose.model("TrustScore", TrustScoreSchema);