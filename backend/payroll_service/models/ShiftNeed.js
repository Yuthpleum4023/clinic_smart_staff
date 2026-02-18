// models/ShiftNeed.js
const mongoose = require("mongoose");

const ApplicantSchema = new mongoose.Schema(
  {
    staffId: { type: String, required: true },
    userId: { type: String, default: "" }, // เก็บไว้ช่วย debug/trace

    // ✅ NEW: เบอร์โทรผู้สมัคร (เก็บเลขล้วน)
    phone: {
      type: String,
      default: "",
      trim: true,
      set: (v) => String(v || "").trim().replace(/[^\d]/g, ""), // เก็บเฉพาะตัวเลข
      validate: {
        validator: function (v) {
          // อนุญาตว่างได้ใน schema (กันข้อมูลเก่า)
          // แต่ฝั่ง controller เราบังคับ required แล้ว
          if (!v) return true;
          return v.length >= 9 && v.length <= 10;
        },
        message: "phone must be 9-10 digits",
      },
    },

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

    // =========================================================
    // ✅ NEW — Clinic Navigation Data (สำหรับ Helper กดนำทาง)
    // - ไม่กระทบของเดิม (ค่า default เป็น null/"" ทั้งหมด)
    // - เก็บไว้ใน need เพื่อให้ approve -> Shift.copy ไปได้ทันที
    // =========================================================
    clinicLat: { type: Number, default: null },
    clinicLng: { type: Number, default: null },

    clinicName: { type: String, default: "" },
    clinicPhone: { type: String, default: "" },
    clinicAddress: { type: String, default: "" },
  },
  { timestamps: true }
);

// index เดิม/เพิ่มเพื่อค้นเร็ว
ShiftNeedSchema.index({ clinicId: 1, status: 1, date: 1, start: 1 });

module.exports = mongoose.model("ShiftNeed", ShiftNeedSchema);
