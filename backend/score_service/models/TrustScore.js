const mongoose = require("mongoose");

const TrustScoreSchema = new mongoose.Schema(
  {
    staffId: { type: String, required: true, unique: true, index: true },
    trustScore: { type: Number, default: 80 }, // 0-100

    totalShifts: { type: Number, default: 0 },
    completed: { type: Number, default: 0 },
    late: { type: Number, default: 0 },
    noShow: { type: Number, default: 0 },

    // ✅ rename ให้ชัดว่า cancelled แบบไหน
    cancelledEarly: { type: Number, default: 0 },

    lastNoShowAt: { type: Date, default: null },
    flags: { type: [String], default: [] },   // e.g. ["NO_SHOW_30D"]
    badges: { type: [String], default: [] }   // e.g. ["HIGHLY_RELIABLE"]
  },
  { timestamps: true }
);

module.exports = mongoose.model("TrustScore", TrustScoreSchema);
