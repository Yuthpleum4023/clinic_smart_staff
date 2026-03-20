// backend/auth_user_service/models/Invite.js
const mongoose = require("mongoose");

const InviteSchema = new mongoose.Schema(
  {
    inviteCode: {
      type: String,
      required: true,
      unique: true,
      index: true,
      uppercase: true,
      trim: true,
    },

    clinicId: {
      type: String,
      required: true,
      index: true,
      trim: true,
    },

    createdByUserId: {
      type: String,
      required: true,
      index: true,
      trim: true,
    },

    // 🔥 รองรับ 2 role
    role: {
      type: String,
      enum: ["employee", "helper"],
      default: "employee",
    },

    fullName: { type: String, default: "", trim: true },
    phone: { type: String, default: "", trim: true },
    email: { type: String, default: "", lowercase: true, trim: true },

    expiresAt: { type: Date, required: true, index: true },

    usedAt: { type: Date, default: null },
    usedByUserId: { type: String, default: "", trim: true },

    isRevoked: { type: Boolean, default: false },
  },
  { timestamps: true }
);

// 🔥 ป้องกันใช้ invite ซ้ำระดับ DB
InviteSchema.index(
  { inviteCode: 1, usedAt: 1 },
  {
    unique: true,
    partialFilterExpression: { usedAt: null },
  }
);

module.exports = mongoose.model("Invite", InviteSchema);