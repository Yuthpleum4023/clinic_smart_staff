// backend/auth_user_service/routes/subscriptionRoutes.js
const router = require("express").Router();
const ctrl = require("../controllers/subscriptionController");

// ✅ สมมติ auth middleware ของ auth_user_service ชื่อ auth และ requireRole มีอยู่แล้ว
// ถ้าของท่านชื่อไม่ตรง เปลี่ยน import ให้ตรงโปรเจกต์จริง
const { auth, requireRole } = require("../middleware/auth");

// ดู subscription ของตัวเอง
router.get("/me", auth, ctrl.me);

// ✅ เปิด premium (หลังจ่ายเงิน) — แนะนำให้ admin หรือ system/internal เรียก
router.post("/activate", auth, requireRole(["admin"]), ctrl.activate);

// ยกเลิก (admin ยกเลิกให้ user หรือ user ยกเลิกของตัวเองก็ได้ — ตอนนี้ให้ admin ก่อน)
router.post("/cancel", auth, requireRole(["admin"]), ctrl.cancel);

module.exports = router;