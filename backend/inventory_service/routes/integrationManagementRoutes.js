const router = require("express").Router();

const {
  auth,
  requireClinic,
  requireRole,
} = require("../middleware/auth");

const ctrl = require(
  "../controllers/integrationManagementController"
);

router.use(
  auth,
  requireClinic,
  requireRole(["admin"])
);

router.get(
  "/connectors",
  ctrl.listConnectors
);

router.post(
  "/connectors",
  ctrl.createConnector
);

router.patch(
  "/connectors/:connectorId",
  ctrl.updateConnector
);

router.post(
  "/connectors/:connectorId/rotate-credential",
  ctrl.rotateCredential
);

router.get(
  "/connectors/:connectorId/mappings",
  ctrl.listMappings
);

router.post(
  "/connectors/:connectorId/mappings",
  ctrl.createMapping
);

router.patch(
  "/mappings/:mappingId",
  ctrl.updateMapping
);

module.exports = router;
