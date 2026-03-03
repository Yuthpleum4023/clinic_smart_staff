// backend/auth_user_service/models/Subscription.js
const mongoose = require("mongoose");

const PLAN_ENUM = ["free", "premium"];
const STATUS_ENUM = ["inactive", "active", "cancelled", "expired"];

const SubscriptionSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, index: true },
    clinicId: { type: String, default: "", index: true },

    plan: { type: String, enum: PLAN_ENUM, default: "free", index: true },
    status: { type: String, enum: STATUS_ENUM, default: "inactive", index: true },

    // วันเริ่ม/วันหมดอายุของสิทธิ์
    startedAt: { type: Date, default: null },
    premiumUntil: { type: Date, default: null, index: true },

    // เก็บ reference ภายนอก (ถ้ามี): slip id, order id, payment provider id
    externalRef: { type: String, default: "", index: true },

    // ประวัติรายการ (กัน webhook ยิงซ้ำ)
    events: {
      type: [
        {
          type: { type: String, default: "" }, // "activate" | "renew" | "cancel" | "expire" | "webhook"
          at: { type: Date, default: Date.now },
          ref: { type: String, default: "" }, // กันซ้ำด้วย ref
          amount: { type: Number, default: 0 },
          meta: { type: Object, default: {} },
        },
      ],
      default: [],
    },

    // audit
    updatedBy: { type: String, default: "" }, // admin userId หรือ "system"
  },
  { timestamps: true }
);

// 1 user มี subscription เดียว (ง่ายสุด)
SubscriptionSchema.index({ userId: 1 }, { unique: true });

module.exports = mongoose.model("Subscription", SubscriptionSchema);