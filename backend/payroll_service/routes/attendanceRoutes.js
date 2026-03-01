// backend/payroll_service/routes/attendanceRoutes.js
const router = require("express").Router();
const { auth, requireRole } = require("../middleware/auth");

const ctrl = require("../controllers/attendanceController");

// ======================================
// ✅ Premium Anti-fraud: Staff self-attendance only
// - clinic/admin ไม่ควรลงเวลาแทนพนักงานได้
// - ดังนั้น check-in / check-out / my sessions ให้เป็น staff เท่านั้น
// ======================================

// staff/employee (✅ MUST be staff)
router.post("/check-in", auth, requireRole(["staff"]), ctrl.checkIn);

// ✅ NEW (recommended): check-out แบบไม่ต้องส่ง session id
// เหมาะกับ production: backend หา active session ของ user แล้วปิดให้
// (ไม่ลบของเก่า เพื่อ backward compatible)
router.post("/check-out", auth, requireRole(["staff"]), ctrl.checkOut);

// ✅ Backward compatible: ถ้า client เก่ามีการส่ง session id มา
// IMPORTANT: controller ต้อง verify ว่า session นี้เป็นของ user คนนี้จริง
router.post("/:id/check-out", auth, requireRole(["staff"]), ctrl.checkOut);

router.get("/me", auth, requireRole(["staff"]), ctrl.listMySessions);

// ✅ optional: วันเดียว + ค่าจ้าง/OT preview (ดึง staff_service)
router.get("/me-preview", auth, requireRole(["staff"]), ctrl.myDayPreview);

// admin (clinic view / reports)
router.get("/clinic", auth, requireRole(["admin"]), ctrl.listClinicSessions);

module.exports = router;