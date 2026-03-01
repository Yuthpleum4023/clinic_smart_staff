// payroll_service/routes/clinicRoutes.js
const router = require("express").Router();
const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/clinicController");

// ✅ NEW — Brand Controller
const brand = require("../controllers/clinicBrandController");

// =========================================================
// ✅ ดูข้อมูลคลินิก (ต้อง login)
// GET /clinics/:clinicId
// =========================================================
router.get("/:clinicId", auth, ctrl.getClinic);

// =========================================================
// ✅ เปลี่ยนชื่อ/โปรไฟล์ "คลินิกตัวเอง" (admin เท่านั้น)
// PATCH /clinics/me/profile
// body: { clinicName?, clinicPhone?, clinicAddress? }
// =========================================================
router.patch("/me/profile", auth, requireRole(["admin"]), ctrl.patchMyClinicProfile);

// =========================================================
// ✅ อัปเดตพิกัด "คลินิกตัวเอง" (admin เท่านั้น)
// PATCH /clinics/me/location
// body: { clinicLat, clinicLng, clinicName, clinicPhone, clinicAddress, backfill? }
// =========================================================
router.patch(
  "/me/location",
  auth,
  requireRole(["admin"]),

  // ✅✅✅ LOG MIDDLEWARE (สำคัญมาก)
  (req, res, next) => {
    console.log("======================================");
    console.log("📍 PATCH /clinics/me/location HIT");
    console.log("Host:", req.get("host"));
    console.log("Authorization:", req.get("authorization") ? "YES" : "NO");
    console.log("Content-Type:", req.get("content-type"));
    console.log("Body:", req.body);
    console.log("User(from auth middleware):", req.user);
    console.log("======================================");
    next();
  },

  ctrl.patchMyClinicLocation
);

// =========================================================
// ✅ อัปเดตพิกัดคลินิก (admin เท่านั้น) — ของเดิมยังอยู่
// PATCH /clinics/:clinicId/location
// =========================================================
router.patch("/:clinicId/location", auth, requireRole(["admin"]), ctrl.patchClinicLocation);

// =========================================================
// ✅ NEW — SaaS Branding System (Monogram Logo) (admin เท่านั้น)
// PATCH /clinics/brand
// body: { clinicId, brandAbbr, brandColor }
// =========================================================
router.patch("/brand", auth, requireRole(["admin"]), brand.updateClinicBrand);

module.exports = router;