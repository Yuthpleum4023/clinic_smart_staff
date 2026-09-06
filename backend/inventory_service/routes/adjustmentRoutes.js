const router = require("express").Router();
const { auth, requireClinic, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/adjustmentController");

router.use(auth, requireClinic);

router.post(
  "/",
  requireRole(["employee"]),
  ctrl.createRequest
);

router.get(
  "/pending",
  requireRole(["admin"]),
  ctrl.listPending
);

router.post(
  "/:id/approve",
  requireRole(["admin"]),
  ctrl.approve
);

router.post(
  "/:id/reject",
  requireRole(["admin"]),
  ctrl.reject
);

module.exports = router;
