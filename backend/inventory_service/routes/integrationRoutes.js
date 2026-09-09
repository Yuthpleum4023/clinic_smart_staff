const router = require(
  "express"
).Router();

const {
  connectorAuth,
} = require(
  "../middleware/connectorAuth"
);

const ctrl = require(
  "../controllers/integrationIngestionController"
);

// External connector boundary.
//
// Deliberately separate from:
// - user JWT auth
// - requireClinic
// - requireRole
// - INTERNAL_SERVICE_KEY
router.post(
  "/movements",
  connectorAuth,
  ctrl.movement
);

// Legacy consumption-only path retained for
// backward compatibility with existing clients.
router.post(
  "/consumption",
  connectorAuth,
  ctrl.consume
);

module.exports = router;
