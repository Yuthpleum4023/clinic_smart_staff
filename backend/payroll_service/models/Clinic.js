// payroll_service/models/Clinic.js
const mongoose = require("mongoose");

const ClinicSchema = new mongoose.Schema(
  {
    // ✅ ใช้ clinicId แบบ cln_xxx เป็นหลัก (อิสระจาก _id)
    clinicId: { type: String, required: true, unique: true, index: true },

    name: { type: String, default: "" },
    phone: { type: String, default: "" },
    address: { type: String, default: "" },

    // -----------------------------
    // 📍 Location (ใช้คำนวณระยะ)
    // -----------------------------
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },

    // เขต/อำเภอ
    district: { type: String, default: "" },

    // จังหวัด
    province: { type: String, default: "" },

    // label พร้อมใช้โชว์ UI เช่น "ถลาง, ภูเก็ต"
    locationLabel: { type: String, default: "" },

    // -----------------------------
    // 🎨 SaaS Branding
    // -----------------------------
    brandAbbr: { type: String, default: "" },   // เช่น MC
    brandColor: { type: String, default: "" },  // เช่น #6D28D9
  },
  { timestamps: true }
);

// -----------------------------
// Index
// -----------------------------
ClinicSchema.index({ clinicId: 1 });
ClinicSchema.index({ lat: 1, lng: 1 });

module.exports = mongoose.model("Clinic", ClinicSchema);