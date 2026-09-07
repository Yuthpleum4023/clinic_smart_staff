const {
  resolveInventoryActor,
} = require("../services/actorService");

const {
  listConnectors,
  createConnector,
  updateConnector,
  rotateConnectorCredential,
  listMappings,
  createMapping,
  updateMapping,
} = require("../services/integrationManagementService");

async function adminActor(req) {
  const actor = await resolveInventoryActor(req);

  if (!actor.hasAdmin) {
    const err = new Error("Admin only");
    err.status = 403;
    err.code = "ADMIN_ONLY";
    throw err;
  }

  return actor;
}

exports.listConnectors = async (req, res, next) => {
  try {
    const actor = await adminActor(req);
    const connectors = await listConnectors({
      clinicId: actor.clinicId,
    });

    return res.json({
      ok: true,
      connectors,
    });
  } catch (err) {
    return next(err);
  }
};

exports.createConnector = async (req, res, next) => {
  try {
    const actor = await adminActor(req);
    const result = await createConnector({
      clinicId: actor.clinicId,
      actorUserId: actor.userId,
      input: req.body,
    });

    return res.status(201).json({
      ok: true,
      ...result,
    });
  } catch (err) {
    return next(err);
  }
};

exports.updateConnector = async (req, res, next) => {
  try {
    const actor = await adminActor(req);
    const connector = await updateConnector({
      clinicId: actor.clinicId,
      connectorId: req.params.connectorId,
      actorUserId: actor.userId,
      input: req.body,
    });

    return res.json({
      ok: true,
      connector,
    });
  } catch (err) {
    return next(err);
  }
};

exports.rotateCredential = async (req, res, next) => {
  try {
    const actor = await adminActor(req);
    const result = await rotateConnectorCredential({
      clinicId: actor.clinicId,
      connectorId: req.params.connectorId,
      actorUserId: actor.userId,
    });

    return res.json({
      ok: true,
      ...result,
    });
  } catch (err) {
    return next(err);
  }
};

exports.listMappings = async (req, res, next) => {
  try {
    const actor = await adminActor(req);
    const mappings = await listMappings({
      clinicId: actor.clinicId,
      connectorId: req.params.connectorId,
    });

    return res.json({
      ok: true,
      mappings,
    });
  } catch (err) {
    return next(err);
  }
};

exports.createMapping = async (req, res, next) => {
  try {
    const actor = await adminActor(req);
    const mapping = await createMapping({
      clinicId: actor.clinicId,
      connectorId: req.params.connectorId,
      actorUserId: actor.userId,
      input: req.body,
    });

    return res.status(201).json({
      ok: true,
      mapping,
    });
  } catch (err) {
    return next(err);
  }
};

exports.updateMapping = async (req, res, next) => {
  try {
    const actor = await adminActor(req);
    const mapping = await updateMapping({
      clinicId: actor.clinicId,
      mappingId: req.params.mappingId,
      actorUserId: actor.userId,
      input: req.body,
    });

    return res.json({
      ok: true,
      mapping,
    });
  } catch (err) {
    return next(err);
  }
};
