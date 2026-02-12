// models/ResetToken.js
const mongoose = require("mongoose");

const ResetTokenSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },
    code: { type: String, required: true }, // OTP 6 หลัก (string)
    expiresAt: { type: Date, required: true, index: true },
  },
  { timestamps: true }
);

// ✅ TTL: ลบเอกสารหลัง expiresAt ถึงเวลา (MongoDB background task)
ResetTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

// ✅ ป้องกันยิงรัว (optional): userId + code ซ้ำไม่เก็บซ้อน
ResetTokenSchema.index({ userId: 1, code: 1 }, { unique: true });

module.exports = mongoose.model("ResetToken", ResetTokenSchema);
