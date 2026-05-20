const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const uploadClinicLogo = require("../middleware/uploadClinicLogo");
const ctrl = require("../controllers/clinicLogoController");

const ADMIN_ROLES = ["admin", "clinic_admin"];

/**
 * Clinic Logo Upload Routes
 *
 * Mounted from server.js as:
 *   app.use("/upload", clinicLogoRoutes);
 *   app.use("/api/upload", clinicLogoRoutes);
 *
 * Final endpoints:
 *   POST   /upload/logo/:clinicId
 *   POST   /api/upload/logo/:clinicId
 *   DELETE /upload/logo/:clinicId
 *   DELETE /api/upload/logo/:clinicId
 */

// ✅ Upload / replace clinic logo
router.post(
  "/logo/:clinicId",
  auth,
  requireRole(ADMIN_ROLES),
  uploadClinicLogo.single("logo"),
  ctrl.uploadClinicLogo
);

// ✅ Remove clinic logo
router.delete(
  "/logo/:clinicId",
  auth,
  requireRole(ADMIN_ROLES),
  ctrl.removeClinicLogo
);

module.exports = router;
