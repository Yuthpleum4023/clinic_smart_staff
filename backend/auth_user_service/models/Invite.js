const mongoose = require("mongoose");

const InviteSchema = new mongoose.Schema(
  {
    inviteCode: { type: String, required: true, unique: true, index: true },
    clinicId: { type: String, required: true, index: true },
    createdByUserId: { type: String, required: true, index: true },

    role: { type: String, enum: ["employee"], default: "employee" },

    // optional: prefill
    fullName: { type: String, default: "" },
    phone: { type: String, default: "" },
    email: { type: String, default: "" },

    expiresAt: { type: Date, required: true, index: true },
    usedAt: { type: Date, default: null },
    usedByUserId: { type: String, default: "" },
    isRevoked: { type: Boolean, default: false },
  },
  { timestamps: true }
);

module.exports = mongoose.model("Invite", InviteSchema);
