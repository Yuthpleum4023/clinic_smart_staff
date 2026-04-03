const mongoose = require("mongoose");

const ClinicSchema = new mongoose.Schema(
  {
    // ✅ ใช้ clinicId แบบ cln_xxx เป็นหลัก (อิสระจาก _id)
    clinicId: { type: String, required: true, unique: true, index: true },

    name: { type: String, default: "", trim: true },
    phone: { type: String, default: "", trim: true },
    address: { type: String, default: "", trim: true },

    // ✅ NEW: ใช้สำหรับเอกสาร / PDF / profile คลินิก
    branchName: { type: String, default: "", trim: true },
    taxId: { type: String, default: "", trim: true },
    logoUrl: { type: String, default: "", trim: true },

    // -----------------------------
    // 📍 Location (ใช้คำนวณระยะ)
    // -----------------------------
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },

    // เขต/อำเภอ
    district: { type: String, default: "", trim: true },

    // จังหวัด
    province: { type: String, default: "", trim: true },

    // label พร้อมใช้โชว์ UI เช่น "ถลาง, ภูเก็ต"
    locationLabel: { type: String, default: "", trim: true },

    // -----------------------------
    // 🎨 SaaS Branding
    // -----------------------------
    brandAbbr: { type: String, default: "", trim: true }, // เช่น MC
    brandColor: { type: String, default: "", trim: true }, // เช่น #6D28D9

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