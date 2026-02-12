const mongoose = require("mongoose");

/**
 * ================================
 * Tax Profile (ข้อมูลลดหย่อนภาษีรายปี)
 * - กรอกได้ / ข้ามได้
 * - เก็บเป็นบาท/ปี (annual)
 * ================================
 */
const TaxProfileSchema = new mongoose.Schema(
  {
    taxYear: { type: Number, required: true }, // เช่น 2026

    // สถานะครอบครัว
    maritalStatus: {
      type: String,
      enum: ["single", "married_no_income", "married_with_income"],
      default: "single",
    },
    childrenCount: { type: Number, default: 0, min: 0 },

    // อุปการะพ่อแม่
    supportFather: { type: Boolean, default: false },
    supportMother: { type: Boolean, default: false },
    supportSpouseFather: { type: Boolean, default: false },
    supportSpouseMother: { type: Boolean, default: false },

    // ประกัน / กองทุน (บาท/ปี)
    lifeInsurance: { type: Number, default: 0, min: 0 },
    healthInsuranceSelf: { type: Number, default: 0, min: 0 },
    healthInsuranceParents: { type: Number, default: 0, min: 0 },
    ssf: { type: Number, default: 0, min: 0 },
    rmf: { type: Number, default: 0, min: 0 },
    pvd: { type: Number, default: 0, min: 0 },

    // บ้าน
    homeLoanInterest: { type: Number, default: 0, min: 0 },

    // บริจาค
    donation: { type: Number, default: 0, min: 0 },
    donationEducation: { type: Number, default: 0, min: 0 },

    updatedAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

const UserSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, unique: true, index: true }, // USR_xxx

    // ✅ clinic tenancy (MVP: employee อยู่คลินิกเดียวก่อน)
    clinicId: { type: String, required: true, index: true }, // CLN_xxx

    role: {
      type: String,
      enum: ["admin", "employee"],
      required: true,
      index: true,
    },

    // ✅ staffId = ตัวตน "ผู้ช่วย/พนักงาน" ข้ามคลินิก
    staffId: { type: String, default: "" }, // STF_xxx

    // login
    email: { type: String, default: "", index: true },
    phone: { type: String, default: "", index: true },
    passwordHash: { type: String, required: true },

    // employee profile (optional)
    fullName: { type: String, default: "" },
    employeeCode: { type: String, default: "" }, // EMP_xxx (optional)

    isActive: { type: Boolean, default: true },

    /**
     * ================================
     * ✅ Tax Profiles (ลดหย่อนภาษี)
     * - array ต่อปี
     * - ถ้าไม่กรอก => array ว่าง
     * ================================
     */
    taxProfiles: {
      type: [TaxProfileSchema],
      default: [],
    },
  },
  { timestamps: true }
);

// -------------------- Indexes --------------------

// unique per clinic (optional - helps prevent duplicates)
UserSchema.index({ clinicId: 1, email: 1 }, { unique: false });
UserSchema.index({ clinicId: 1, phone: 1 }, { unique: false });

// ✅ helpful index for cross-service lookups
UserSchema.index({ staffId: 1 }, { unique: false });

module.exports = mongoose.model("User", UserSchema);
