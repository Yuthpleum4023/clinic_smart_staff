// payroll_service/models/Clinic.js
const mongoose = require("mongoose");

const ClinicSchema = new mongoose.Schema(
  {
    // ✅ ใช้ clinicId แบบ cln_xxx เป็นหลัก (อิสระจาก _id)
    clinicId: { type: String, required: true, unique: true, index: true },

    name: { type: String, default: "" },
    phone: { type: String, default: "" },
    address: { type: String, default: "" },

    lat: { type: Number, default: null },
    lng: { type: Number, default: null },

    // ✅ NEW — SaaS Branding (Monogram Logo System)
    brandAbbr: { type: String, default: "" },      // เช่น MC
    brandColor: { type: String, default: "" },     // เช่น #6D28D9
  },
  { timestamps: true }
);

module.exports = mongoose.model("Clinic", ClinicSchema);