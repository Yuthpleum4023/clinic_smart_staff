// payroll_service/routes/shiftNeedRoutes.js
const router = require("express").Router();
const auth = require("../middleware/auth");
const ctrl = require("../controllers/shiftNeedController");

// ✅ แนะนำให้เอา /open ไว้ก่อน route ที่มี /:id กันสับสนในอนาคต
// staff
router.get("/open", auth, ctrl.listOpenNeeds);
router.post("/:id/apply", auth, ctrl.applyNeed);

// admin
router.post("/", auth, ctrl.createNeed);
router.get("/", auth, ctrl.listClinicNeeds);
router.get("/:id/applicants", auth, ctrl.listApplicants);
router.post("/:id/approve", auth, ctrl.approveApplicant);
router.patch("/:id/cancel", auth, ctrl.cancelNeed);

module.exports = router;
