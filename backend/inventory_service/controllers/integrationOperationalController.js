const {
  resolveInventoryActor,
} = require("../services/actorService");

const {
  getConnectorHealth,
  listIntegrationEvents,
  getIntegrationEvent,
  reprocessIntegrationEvent,
} = require(
  "../services/integrationOperationalService"
);

async function adminActor(req) {
  const actor =
    await resolveInventoryActor(req);

  if (!actor.hasAdmin) {
    const err =
      new Error("Admin only");
    err.status = 403;
    err.code = "ADMIN_ONLY";
    throw err;
  }

  return actor;
}

exports.getConnectorHealth =
  async (req, res, next) => {
    try {
      const actor =
        await adminActor(req);

      const health =
        await getConnectorHealth({
          clinicId:
            actor.clinicId,
          connectorId:
            req.params.connectorId,
        });

      return res.json({
        ok: true,
        health,
      });
    } catch (err) {
      return next(err);
    }
  };

exports.listEvents =
  async (req, res, next) => {
    try {
      const actor =
        await adminActor(req);

      const events =
        await listIntegrationEvents({
          clinicId:
            actor.clinicId,
          connectorId:
            req.params.connectorId,
          status:
            req.query?.status,
          limit:
            req.query?.limit,
        });

      return res.json({
        ok: true,
        events,
      });
    } catch (err) {
      return next(err);
    }
  };

exports.getEvent =
  async (req, res, next) => {
    try {
      const actor =
        await adminActor(req);

      const event =
        await getIntegrationEvent({
          clinicId:
            actor.clinicId,
          eventId:
            req.params.eventId,
        });

      return res.json({
        ok: true,
        event,
      });
    } catch (err) {
      return next(err);
    }
  };

exports.reprocessEvent =
  async (req, res, next) => {
    try {
      const actor =
        await adminActor(req);

      const result =
        await reprocessIntegrationEvent({
          clinicId:
            actor.clinicId,
          eventId:
            req.params.eventId,
        });

      return res.json({
        ok: true,
        action:
          "integration_event_reprocessed",
        ...result,
      });
    } catch (err) {
      return next(err);
    }
  };
