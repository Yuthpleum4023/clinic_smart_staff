// routes/availabilityRoutes.js
const express = require("express");
const router = express.Router();

const {
  createAvailability,
  listMyAvailabilities,
  cancelAvailability,
  listOpenAvailabilities,
  bookAvailability, // ✅ NEW
} = require("../controllers/availabilityController");

// ✅ หมายเหตุ: สมมติว่าท่านมี middleware auth เช่น requireAuth
// ถ้าชื่อไม่เหมือน ให้แก้บรรทัด require ด้านล่างให้ตรงโปรเจกต์ท่าน
let requireAuth = null;
try {
  requireAuth = require("../middleware/auth"); // <--- ปรับชื่อไฟล์ตามจริง
} catch (_) {
  requireAuth = (req, res, next) => next(); // กันพังตอนยังไม่ผูก auth
}

// ======================================================
// ✅ CLINIC ADMIN
// ======================================================

// browse ตารางว่างผู้ช่วย
router.get("/open", requireAuth, listOpenAvailabilities);

// ✅ NEW — BOOK AVAILABILITY → CREATE SHIFT
router.post("/:id/book", requireAuth, bookAvailability);

// ======================================================
// ✅ STAFF / HELPER
// ======================================================

// my availabilities
router.get("/me", requireAuth, listMyAvailabilities);

// create mine
router.post("/", requireAuth, createAvailability);

// cancel mine
router.patch("/:id/cancel", requireAuth, cancelAvailability);

module.exports = router;