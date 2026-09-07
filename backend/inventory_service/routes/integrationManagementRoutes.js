const router = require("express").Router();

const {
  auth,
  requireClinic,
  requireRole,
} = require("../middleware/auth");

const ctrl = require(
  "../controllers/integrationManagementController"
);

const operationalCtrl = require(
  "../controllers/integrationOperationalController"
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

router.get(
  "/connectors/:connectorId/health",
  operationalCtrl.getConnectorHealth
);

router.get(
  "/connectors/:connectorId/events",
  operationalCtrl.listEvents
);

router.get(
  "/events/:eventId",
  operationalCtrl.getEvent
);

router.post(
  "/events/:eventId/reprocess",
  operationalCtrl.reprocessEvent
);

module.exports = router;
