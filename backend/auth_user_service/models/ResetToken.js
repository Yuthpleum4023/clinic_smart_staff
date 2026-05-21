// models/ResetToken.js
const mongoose = require("mongoose");

const ResetTokenSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },

    // Legacy field: kept for old tokens / migration compatibility.
    // New production flow stores codeHash only.
    code: { type: String, default: "", select: false },

    // Production: store OTP hash, never store raw OTP as source of truth.
    codeHash: { type: String, default: "", select: false },

    expiresAt: { type: Date, required: true, index: true },
  },
  { timestamps: true }
);

ResetTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
ResetTokenSchema.index({ userId: 1, code: 1 }, { unique: true });

module.exports =
  mongoose.models.ResetToken || mongoose.model("ResetToken", ResetTokenSchema);
