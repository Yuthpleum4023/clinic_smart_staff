// backend/payroll_service/routes/attendanceRoutes.js
const router = require("express").Router();
const { auth, requireRole, requireSelfStaff } = require("../middleware/auth");

const ctrl = require("../controllers/attendanceController");

// ======================================
// ✅ Premium Anti-fraud: Staff self-attendance only
// - clinic/admin ไม่ควรลงเวลาแทนพนักงานได้
// - ดังนั้น check-in / check-out / my sessions ให้เป็น "employee" เท่านั้น
// - และต้องเป็น staffId ของตัวเอง (กันปลอม staffId ใน body)
// ======================================

// ✅ MUST be employee/staff (canonical => employee)
// ✅ MUST be self only (allowClinic:false)
router.post(
  "/check-in",
  auth,
  requireRole(["employee"]), // รองรับ staff/emp ผ่าน canonical
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkIn
);

// ✅ NEW (recommended): check-out แบบไม่ต้องส่ง session id
router.post(
  "/check-out",
  auth,
  requireRole(["employee"]),
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkOut
);

// ✅ Backward compatible: ถ้า client เก่ามีการส่ง session id มา
// IMPORTANT: controller ต้อง verify ว่า session นี้เป็นของ user คนนี้จริง
router.post(
  "/:id/check-out",
  auth,
  requireRole(["employee"]),
  requireSelfStaff({ allowClinic: false }),
  ctrl.checkOut
);

router.get(
  "/me",
  auth,
  requireRole(["employee"]),
  requireSelfStaff({ allowClinic: false }),
  ctrl.listMySessions
);

// ✅ optional: วันเดียว + ค่าจ้าง/OT preview (ดึง staff_service)
router.get(
  "/me-preview",
  auth,
  requireRole(["employee"]),
  requireSelfStaff({ allowClinic: false }),
  ctrl.myDayPreview
);

// ======================================
// admin/clinic view (reports) — ถ้าจะเปิดให้คลินิกดูรายงาน
// NOTE: ถ้าท่าน "ไม่อยากให้คลินิกดู" ก็ลบ route นี้ได้เลย
// ======================================
router.get("/clinic", auth, requireRole(["clinic"]), ctrl.listClinicSessions);

module.exports = router;