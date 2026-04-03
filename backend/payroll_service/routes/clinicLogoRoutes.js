const router = require("express").Router();

const uploadClinicLogo = require("../middleware/uploadClinicLogo");
const ctrl = require("../controllers/clinicLogoController");

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
  uploadClinicLogo.single("logo"),
  ctrl.uploadClinicLogo
);

// ✅ Remove clinic logo
router.delete("/logo/:clinicId", ctrl.removeClinicLogo);

module.exports = router;