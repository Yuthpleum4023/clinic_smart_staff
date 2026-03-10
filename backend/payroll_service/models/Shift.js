// payroll_service/models/Shift.js
const mongoose = require("mongoose");

const ShiftSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true },

    /**
     * ✅ รองรับทั้ง employee + helper
     * - employee: ใช้ staffId
     * - helper  : ใช้ helperUserId
     *
     * เดิม staffId required แต่จะทำให้ helper ที่ไม่มี staffId สร้าง shift ไม่ได้
     * จึงปรับเป็น optional และไป validate รวมกับ helperUserId แทน
     */
    staffId: { type: String, default: "", index: true },

    /**
     * ✅ NEW (ยั่งยืน): ผูก “งานของผู้ช่วย marketplace” กับ userId โดยตรง
     * - ช่วยแก้เคส token ไม่มี staffId
     * - optional เพื่อ backward compatible
     */
    helperUserId: { type: String, default: "", index: true },

    date: { type: String, required: true }, // yyyy-MM-dd
    start: { type: String, required: true }, // HH:mm
    end: { type: String, required: true }, // HH:mm

    status: {
      type: String,
      enum: ["scheduled", "completed", "late", "cancelled", "no_show"],
      default: "scheduled",
      index: true,
    },

    minutesLate: { type: Number, default: 0 },

    hourlyRate: { type: Number, default: 0 }, // บาท/ชั่วโมง
    note: { type: String, default: "" },

    // =========================================================
    // ✅ Clinic Navigation Data (ไม่กระทบของเดิม)
    // =========================================================
    clinicLat: { type: Number, default: null },
    clinicLng: { type: Number, default: null },

    clinicName: { type: String, default: "" },
    clinicPhone: { type: String, default: "" },
    clinicAddress: { type: String, default: "" },
  },
  { timestamps: true }
);

/**
 * ✅ VALIDATION:
 * ต้องมี owner อย่างน้อยหนึ่งอย่าง
 * - staffId สำหรับ employee
 * - helperUserId สำหรับ helper
 */
ShiftSchema.pre("validate", function (next) {
  const staffId = String(this.staffId || "").trim();
  const helperUserId = String(this.helperUserId || "").trim();

  if (!staffId && !helperUserId) {
    return next(
      new Error("Shift requires either staffId or helperUserId")
    );
  }

  next();
});

// -------------------- Indexes --------------------

// เดิมของท่าน (employee)
ShiftSchema.index(
  { clinicId: 1, staffId: 1, date: -1 },
  { name: "idx_shift_clinic_staff_date" }
);

// เดิมของท่าน
ShiftSchema.index(
  { clinicId: 1, date: -1, createdAt: -1 },
  { name: "idx_shift_clinic_date_created" }
);
ShiftSchema.index(
  { staffId: 1, date: -1, createdAt: -1 },
  { name: "idx_shift_staff_date_created" }
);

// ✅ helper indexes
ShiftSchema.index(
  { helperUserId: 1, date: -1, createdAt: -1 },
  { name: "idx_shift_helper_date_created" }
);
ShiftSchema.index(
  { clinicId: 1, helperUserId: 1, date: -1 },
  { name: "idx_shift_clinic_helper_date" }
);

// ✅ useful for attendance lookup by day/status
ShiftSchema.index(
  { clinicId: 1, status: 1, date: -1 },
  { name: "idx_shift_clinic_status_date" }
);

// ✅ useful when lookup by owner + exact day
ShiftSchema.index(
  { clinicId: 1, staffId: 1, date: 1, createdAt: -1 },
  { name: "idx_shift_clinic_staff_exact_day" }
);
ShiftSchema.index(
  { clinicId: 1, helperUserId: 1, date: 1, createdAt: -1 },
  { name: "idx_shift_clinic_helper_exact_day" }
);

module.exports = mongoose.model("Shift", ShiftSchema);