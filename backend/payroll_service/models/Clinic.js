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

    // -----------------------------
    // ✅ Payroll / Social Security
    // -----------------------------
    socialSecurity: {
      enabled: { type: Boolean, default: true },

      // เช่น 0.05 = 5%
      employeeRate: { type: Number, default: 0.05 },

      // เพดานฐานค่าจ้างที่ใช้คิด SSO
      // เช่น 17500
      maxWageBase: { type: Number, default: 17500 },
    },
  },
  { timestamps: true }
);

// -----------------------------
// Index
// -----------------------------
ClinicSchema.index({ clinicId: 1 });
ClinicSchema.index({ lat: 1, lng: 1 });

module.exports = mongoose.model("Clinic", ClinicSchema);