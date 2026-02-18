// payroll_service/routes/clinicRoutes.js
const router = require("express").Router();
const auth = require("../middleware/auth");
const ctrl = require("../controllers/clinicController");

// ✅ ดูข้อมูลคลินิก (ต้อง login)
// GET /clinics/:clinicId
router.get("/:clinicId", auth, ctrl.getClinic);

// ✅ อัปเดตพิกัด "คลินิกตัวเอง" (admin เท่านั้น)
// PATCH /clinics/me/location
// body: { clinicLat, clinicLng, clinicName, clinicPhone, clinicAddress, backfill? }
router.patch("/me/location", auth, ctrl.patchMyClinicLocation);

// ✅ อัปเดตพิกัดคลินิก (admin เท่านั้น) — ของเดิมยังอยู่
// PATCH /clinics/:clinicId/location
router.patch("/:clinicId/location", auth, ctrl.patchClinicLocation);

module.exports = router;
