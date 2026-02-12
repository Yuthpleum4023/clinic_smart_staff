// models/ShiftNeed.js
const mongoose = require("mongoose");

const ApplicantSchema = new mongoose.Schema(
  {
    staffId: { type: String, required: true },
    userId: { type: String, default: "" }, // เก็บไว้ช่วย debug/trace
    appliedAt: { type: Date, default: Date.now },
    status: {
      type: String,
      enum: ["pending", "approved", "rejected"],
      default: "pending",
    },
  },
  { _id: false }
);

const ShiftNeedSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },

    title: { type: String, default: "ต้องการผู้ช่วย" },
    role: { type: String, default: "ผู้ช่วย" },

    date: { type: String, required: true }, // yyyy-MM-dd
    start: { type: String, required: true }, // HH:mm
    end: { type: String, required: true }, // HH:mm

    hourlyRate: { type: Number, required: true },
    requiredCount: { type: Number, default: 1 },

    note: { type: String, default: "" },

    status: {
      type: String,
      enum: ["open", "filled", "cancelled"],
      default: "open",
      index: true,
    },

    applicants: { type: [ApplicantSchema], default: [] },

    createdByUserId: { type: String, default: "" }, // admin userId
  },
  { timestamps: true }
);

module.exports = mongoose.model("ShiftNeed", ShiftNeedSchema);
