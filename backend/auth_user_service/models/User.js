// backend/auth_user_service/models/User.js
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

/**
 * ================================
 * ✅ Multi-role (ระยะยาว)
 * - roles: ["employee","helper","admin"]  (หลายบทบาท)
 * - activeRole: บทบาทที่กำลังใช้งาน (token ต้องใส่ตามนี้)
 *
 * ✅ Backward compatible
 * - role (เดิม) ยังเก็บไว้ เพื่อ service เก่าอ่านได้
 * - เราจะ sync role = activeRole ใน hook
 * ================================
 */
const ROLE_ENUM = ["admin", "employee", "helper"];

const UserSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, unique: true, index: true }, // USR_xxx

    // ✅ clinic tenancy (MVP: employee อยู่คลินิกเดียวก่อน)
    clinicId: { type: String, required: true, index: true }, // CLN_xxx

    /**
     * ✅ NEW: roles[] (multi-role)
     * - เก็บบทบาททั้งหมดที่ user นี้มี
     * - ค่าเริ่มต้น: ถ้ายังใช้ระบบเดิม -> จะถูก backfill จาก role (เดิม) ใน hook
     */
    roles: {
      type: [String],
      enum: ROLE_ENUM,
      default: [],
      index: true,
    },

    /**
     * ✅ NEW: activeRole
     * - role ที่ “กำลังใช้งาน” ตอนนี้
     * - token ควรใส่ role = activeRole เท่านั้น
     */
    activeRole: {
      type: String,
      enum: ROLE_ENUM,
      default: "employee",
      index: true,
    },

    /**
     * ⚠️ Legacy field: role (เดิม)
     * - คงไว้กันระบบเก่าพัง
     * - hook จะ sync ให้ role = activeRole อัตโนมัติ
     */
    role: {
      type: String,
      enum: ROLE_ENUM, // ขยายให้รองรับ helper ด้วย
      default: "employee",
      required: true,
      index: true,
    },

    /**
     * ✅ staffId = ตัวตน "พนักงาน/ผู้ช่วย" ข้ามคลินิก
     * - ถ้า activeRole = employee -> จำเป็นต้องมี staffId
     * - ถ้า activeRole = helper -> อาจมีหรือไม่มีก็ได้ (ตาม design ของท่าน)
     *
     * หมายเหตุ: การ enforce แบบ “ห้ามว่าง” จะทำใน login/token/guard จะปลอดภัยกว่า
     */
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

// ✅ NEW helpful indexes
UserSchema.index({ clinicId: 1, activeRole: 1 }, { unique: false });
UserSchema.index({ clinicId: 1, roles: 1 }, { unique: false });

/**
 * ================================
 * ✅ Hooks: Backfill + Sync
 * - ทำให้เอกสารเก่า (ที่มี role อย่างเดียว) ยังทำงานได้
 * - และป้องกัน “ฟีเจอร์หาย” เพราะ activeRole/roles ไม่สัมพันธ์กัน
 * ================================
 */
UserSchema.pre("validate", function (next) {
  try {
    // 1) ถ้า roles ว่าง แต่มี role เดิม -> backfill
    if ((!this.roles || this.roles.length === 0) && this.role) {
      const r = String(this.role).trim();
      if (r) this.roles = [r];
    }

    // 2) ถ้า activeRole ว่าง -> ใช้ role เดิม หรือค่าแรกใน roles
    if (!this.activeRole) {
      const legacy = String(this.role || "").trim();
      const first = Array.isArray(this.roles) && this.roles.length > 0 ? this.roles[0] : "";
      this.activeRole = legacy || first || "employee";
    }

    // 3) ทำให้แน่ใจว่า activeRole อยู่ใน roles เสมอ
    if (this.activeRole) {
      const ar = String(this.activeRole).trim();
      const set = new Set((this.roles || []).map((x) => String(x).trim()).filter(Boolean));
      if (ar) set.add(ar);
      this.roles = Array.from(set);
    }

    // 4) Sync legacy role = activeRole (สำคัญ: service อื่น/โค้ดเก่าอ่าน role)
    if (this.activeRole) {
      this.role = this.activeRole;
    }

    return next();
  } catch (e) {
    return next(e);
  }
});

module.exports = mongoose.model("User", UserSchema);