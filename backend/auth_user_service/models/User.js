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
 * ✅ Location
 * - ใช้ได้ทั้ง helper / employee / admin
 * - เก็บพิกัดล่าสุดของ user
 * - ✅ NEW: เก็บ district / province / address เป็น master data
 * ================================
 */
const UserLocationSchema = new mongoose.Schema(
  {
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },

    district: { type: String, default: "" },
    province: { type: String, default: "" },
    address: { type: String, default: "" },

    // เช่น "หาดใหญ่, สงขลา"
    label: { type: String, default: "" },

    updatedAt: { type: Date, default: null },
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

/**
 * ================================
 * ✅ Subscription / Plan (Premium 299/เดือน)
 * - plan: free | premium
 * - premiumUntil: วันหมดอายุ (ถ้า null/อดีต => ถือว่า free)
 * ================================
 */
const PLAN_ENUM = ["free", "premium"];

const UserSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, unique: true, index: true }, // usr_xxx

    /**
     * ✅ clinic tenancy
     * - admin / employee : ควรมี clinicId
     * - helper           : ไม่จำเป็นต้องมี clinicId ถาวร
     * - enforcement ให้ทำใน controller/service ตาม business flow
     */
    clinicId: { type: String, default: "", index: true }, // cln_xxx หรือ ""

    /**
     * ✅ OPTIONAL: remember first clinic from invite
     * - useful for helper onboarding / analytics / default suggestions
     * - ไม่ใช่ binding หลัก
     */
    firstClinicId: { type: String, default: "", index: true },

    /**
     * ✅ NEW: roles[] (multi-role)
     * - เก็บบทบาททั้งหมดที่ user นี้มี
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
     */
    role: {
      type: String,
      enum: ROLE_ENUM,
      default: "employee",
      required: true,
      index: true,
    },

    /**
     * ✅ staffId = ตัวตน "พนักงาน/ผู้ช่วย"
     * - employee: ต้องมี staffId
     * - helper: อาจมีหรือไม่มีก็ได้
     */
    staffId: { type: String, default: "" }, // stf_xxx

    // login
    email: { type: String, default: "", index: true },
    phone: { type: String, default: "", index: true },
    passwordHash: { type: String, required: true },

    // employee profile (optional)
    fullName: { type: String, default: "" },
    employeeCode: { type: String, default: "" }, // emp_xxx (optional)

    /**
     * ================================
     * ✅ User Location (MASTER)
     * ================================
     */
    location: {
      type: UserLocationSchema,
      default: () => ({
        lat: null,
        lng: null,
        district: "",
        province: "",
        address: "",
        label: "",
        updatedAt: null,
      }),
    },

    isActive: { type: Boolean, default: true },

    /**
     * ================================
     * ✅ Premium Plan fields
     * ================================
     */
    plan: {
      type: String,
      enum: PLAN_ENUM,
      default: "free",
      index: true,
    },
    premiumUntil: { type: Date, default: null, index: true },
    planUpdatedAt: { type: Date, default: null },

    /**
     * ================================
     * ✅ Tax Profiles (ลดหย่อนภาษี)
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

// per clinic helpful indexes
UserSchema.index({ clinicId: 1, email: 1 }, { unique: false });
UserSchema.index({ clinicId: 1, phone: 1 }, { unique: false });

// first clinic analytics / helper onboarding
UserSchema.index({ firstClinicId: 1 }, { unique: false });

// cross-service lookups
UserSchema.index({ staffId: 1 }, { unique: false });

// multi-role helpers
UserSchema.index({ clinicId: 1, activeRole: 1 }, { unique: false });
UserSchema.index({ clinicId: 1, roles: 1 }, { unique: false });

// premium query helpers
UserSchema.index({ plan: 1, premiumUntil: 1 }, { unique: false });

// location lookup helpers
UserSchema.index({ "location.lat": 1, "location.lng": 1 }, { unique: false });

/**
 * ================================
 * ✅ Hooks: Backfill + Sync
 * - normalize role / activeRole / roles
 * - normalize plan/premiumUntil
 * - normalize location
 * - normalize clinic fields by role
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
      const first =
        Array.isArray(this.roles) && this.roles.length > 0 ? this.roles[0] : "";
      this.activeRole = legacy || first || "employee";
    }

    // 3) activeRole ต้องอยู่ใน roles เสมอ
    if (this.activeRole) {
      const ar = String(this.activeRole).trim();
      const set = new Set(
        (this.roles || []).map((x) => String(x).trim()).filter(Boolean)
      );
      if (ar) set.add(ar);
      this.roles = Array.from(set);
    }

    // 4) Sync legacy role = activeRole
    if (this.activeRole) {
      this.role = this.activeRole;
    }

    // 5) Normalize plan
    const p = String(this.plan || "free").trim().toLowerCase();
    this.plan = PLAN_ENUM.includes(p) ? p : "free";

    // 6) ถ้าไม่ใช่ premium -> premiumUntil = null
    if (this.plan !== "premium") {
      this.premiumUntil = null;
    }

    // 7) Normalize clinic fields
    this.clinicId = String(this.clinicId || "").trim();
    this.firstClinicId = String(this.firstClinicId || "").trim();

    // helper ไม่ควร bind clinic ถาวร
    if (this.activeRole === "helper") {
      this.clinicId = "";
    }

    // 8) Normalize location object
    if (!this.location || typeof this.location !== "object") {
      this.location = {
        lat: null,
        lng: null,
        district: "",
        province: "",
        address: "",
        label: "",
        updatedAt: null,
      };
    }

    const lat =
      this.location.lat === null || this.location.lat === undefined
        ? null
        : Number(this.location.lat);

    const lng =
      this.location.lng === null || this.location.lng === undefined
        ? null
        : Number(this.location.lng);

    this.location.lat = Number.isFinite(lat) ? lat : null;
    this.location.lng = Number.isFinite(lng) ? lng : null;

    this.location.district = String(this.location.district || "").trim();
    this.location.province = String(this.location.province || "").trim();
    this.location.address = String(this.location.address || "").trim();
    this.location.label = String(this.location.label || "").trim();

    if (
      this.location.updatedAt &&
      !(this.location.updatedAt instanceof Date)
    ) {
      const d = new Date(this.location.updatedAt);
      this.location.updatedAt = Number.isFinite(d.getTime()) ? d : null;
    }

    return next();
  } catch (e) {
    return next(e);
  }
});

module.exports = mongoose.model("User", UserSchema);