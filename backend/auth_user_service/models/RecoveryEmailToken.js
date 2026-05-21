// models/RecoveryEmailToken.js
const mongoose = require("mongoose");

const RecoveryEmailTokenSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },

    // Store OTP hash only. Never store raw OTP.
    codeHash: { type: String, required: true, select: false },

    expiresAt: { type: Date, required: true, index: true },
  },
  { timestamps: true }
);

RecoveryEmailTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
RecoveryEmailTokenSchema.index({ userId: 1, email: 1 });

module.exports =
  mongoose.models.RecoveryEmailToken ||
  mongoose.model("RecoveryEmailToken", RecoveryEmailTokenSchema);
