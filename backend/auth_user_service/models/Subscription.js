// backend/auth_user_service/models/Subscription.js
const mongoose = require("mongoose");

const PLAN_ENUM = ["free", "premium"];
const STATUS_ENUM = ["inactive", "active", "cancelled", "expired"];

const FEATURE_STATUS_ENUM = ["enabled", "disabled"];

const SubscriptionSchema = new mongoose.Schema(
  {
    // ✅ IMPORTANT:
    // Subscription ของ Clinic Smart Staff ต้องผูกกับ clinicId เป็นหลัก
    // ไม่ใช่ผูกกับ employee/helper รายคน
    clinicId: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },

    // ✅ คนที่เป็นเจ้าของ/แอดมินคลินิก หรือคนที่ระบบเปิดสิทธิ์ให้
    // ใช้เพื่อ audit เท่านั้น ไม่ใช่ตัวตัดสินสิทธิ์ของ employee/helper
    ownerUserId: {
      type: String,
      default: "",
      trim: true,
      index: true,
    },

    // ✅ legacy field:
    // เก็บไว้ชั่วคราวเพื่อไม่ให้ข้อมูลเก่า/โค้ดเก่าพังทันที
    // แต่ห้ามใช้ field นี้เป็นตัวตัดสิน Premium อีกต่อไป
    userId: {
      type: String,
      default: "",
      trim: true,
      index: true,
    },

    plan: {
      type: String,
      enum: PLAN_ENUM,
      default: "free",
      index: true,
    },

    status: {
      type: String,
      enum: STATUS_ENUM,
      default: "inactive",
      index: true,
    },

    // วันเริ่ม/วันหมดอายุของสิทธิ์ Premium ทั้งคลินิก
    startedAt: {
      type: Date,
      default: null,
    },

    premiumUntil: {
      type: Date,
      default: null,
      index: true,
    },

    // ✅ feature-level entitlement
    // ตอนนี้ใช้กับ biometric attendance ก่อน
    // อนาคตเพิ่ม payroll, reports, stock card ได้
    features: {
      biometricAttendance: {
        status: {
          type: String,
          enum: FEATURE_STATUS_ENUM,
          default: "enabled",
        },
        startedAt: {
          type: Date,
          default: null,
        },
        premiumUntil: {
          type: Date,
          default: null,
        },
      },
    },

    // เก็บ reference ภายนอก เช่น slip id, order id, payment provider id
    externalRef: {
      type: String,
      default: "",
      trim: true,
      index: true,
    },

    // ประวัติรายการ กัน webhook/admin action ยิงซ้ำ
    events: {
      type: [
        {
          type: {
            type: String,
            default: "",
          }, // "activate" | "renew" | "cancel" | "expire" | "webhook"
          at: {
            type: Date,
            default: Date.now,
          },
          ref: {
            type: String,
            default: "",
          },
          amount: {
            type: Number,
            default: 0,
          },
          meta: {
            type: Object,
            default: {},
          },
        },
      ],
      default: [],
    },

    // audit
    updatedBy: {
      type: String,
      default: "",
      trim: true,
    },
  },
  { timestamps: true }
);

// ✅ 1 clinic มี subscription เดียว
// ใช้ partial index เพื่อกันปัญหาข้อมูลเก่า clinicId ว่าง
SubscriptionSchema.index(
  { clinicId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      clinicId: { $type: "string", $ne: "" },
    },
  }
);

// query ทั่วไป
SubscriptionSchema.index({ clinicId: 1, status: 1, premiumUntil: 1 });
SubscriptionSchema.index({ ownerUserId: 1 });
SubscriptionSchema.index({ externalRef: 1 });

module.exports = mongoose.model("Subscription", SubscriptionSchema);