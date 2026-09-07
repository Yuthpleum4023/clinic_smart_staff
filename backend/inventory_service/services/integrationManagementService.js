const mongoose = require("mongoose");

const ConnectorConfig = require("../models/ConnectorConfig");
const InventoryItemMapping = require("../models/InventoryItemMapping");
const StockItem = require("../models/StockItem");

const {
  generateConnectorCredential,
} = require("./connectorCredentialService");

const { s } = require("../utils/strings");

function codedError(message, code, status = 400, details = null) {
  const err = new Error(message);
  err.code = code;
  err.status = status;
  if (details) err.details = details;
  return err;
}

function hasOwn(value, key) {
  return !!value && Object.prototype.hasOwnProperty.call(value, key);
}

function objectId(value, label) {
  const raw = s(value);
  if (!mongoose.Types.ObjectId.isValid(raw)) {
    throw codedError(
      `${label} is invalid`,
      "INVALID_OBJECT_ID",
      400,
      { field: label }
    );
  }
  return raw;
}

function requiredString(value, label) {
  const text = s(value);
  if (!text) {
    throw codedError(
      `${label} is required`,
      "REQUIRED_FIELD",
      400,
      { field: label }
    );
  }
  return text;
}

function positiveSafeInteger(value, label, defaultValue = null) {
  const raw =
    value === undefined || value === null || value === ""
      ? defaultValue
      : value;

  const n = Number(raw);

  if (!Number.isSafeInteger(n) || n <= 0) {
    throw codedError(
      `${label} must be a positive safe integer`,
      "INVALID_CONVERSION_FACTOR",
      400,
      { field: label }
    );
  }

  return n;
}

function requireBoolean(value, label) {
  if (value !== true && value !== false) {
    throw codedError(
      `${label} must be boolean`,
      "INVALID_BOOLEAN",
      400,
      { field: label }
    );
  }
  return value;
}

function assertServerOwnedClinic(input) {
  if (hasOwn(input, "clinicId")) {
    throw codedError(
      "clinicId is server-owned",
      "CLINIC_SCOPE_SERVER_OWNED",
      400
    );
  }
}

function assertConnectorCredentialFieldsNotSupplied(input) {
  const fields = [
    "credentialKeyId",
    "credentialHash",
    "credentialVersion",
    "token",
    "secret",
  ];

  for (const field of fields) {
    if (hasOwn(input, field)) {
      throw codedError(
        "Connector credential fields are server-owned",
        "CONNECTOR_CREDENTIAL_FIELDS_SERVER_OWNED",
        400,
        { field }
      );
    }
  }
}

function assertNoPlainConfiguration(input) {
  if (hasOwn(input, "configuration")) {
    throw codedError(
      "Connector configuration is not accepted by management API V1",
      "CONNECTOR_CONFIGURATION_NOT_SUPPORTED",
      400
    );
  }
}

function connectorView(connector) {
  const obj =
    typeof connector?.toObject === "function"
      ? connector.toObject()
      : { ...connector };

  delete obj.credentialHash;

  return {
    ...obj,
    hasCredential: !!s(obj.credentialKeyId),
  };
}

function mappingView(mapping) {
  return typeof mapping?.toObject === "function"
    ? mapping.toObject()
    : mapping;
}

async function resolveConnectorForClinic({
  clinicId,
  connectorId,
  includeDisabled = true,
}) {
  const id = objectId(connectorId, "connectorId");

  const filter = {
    _id: id,
    clinicId: s(clinicId),
  };

  if (!includeDisabled) {
    filter.enabled = true;
  }

  const connector = await ConnectorConfig.findOne(filter);

  if (!connector) {
    throw codedError(
      "Connector not found",
      "CONNECTOR_NOT_FOUND",
      404
    );
  }

  return connector;
}

async function resolveStockItemForClinic({
  clinicId,
  stockItemId,
  requireActive = true,
}) {
  const id = objectId(stockItemId, "stockItemId");

  const item = await StockItem.findOne({
    _id: id,
    clinicId: s(clinicId),
  });

  if (!item) {
    throw codedError(
      "Stock item not found",
      "STOCK_ITEM_NOT_FOUND",
      404
    );
  }

  if (requireActive && item.active === false) {
    throw codedError(
      "Stock item is inactive",
      "STOCK_ITEM_INACTIVE",
      409
    );
  }

  if (!s(item.unit)) {
    throw codedError(
      "Stock item unit is missing",
      "STOCK_ITEM_UNIT_REQUIRED",
      409
    );
  }

  return item;
}

function duplicateCode(err, fallback) {
  if (Number(err?.code) !== 11000) {
    throw err;
  }

  throw codedError(
    fallback.message,
    fallback.code,
    409
  );
}

async function listConnectors({ clinicId }) {
  const connectors = await ConnectorConfig.find({
    clinicId: s(clinicId),
  })
    .sort({ createdAt: 1 })
    .lean();

  return connectors.map(connectorView);
}

async function createConnector({
  clinicId,
  actorUserId,
  input,
}) {
  const body =
    input && typeof input === "object" ? input : {};

  assertServerOwnedClinic(body);
  assertConnectorCredentialFieldsNotSupplied(body);
  assertNoPlainConfiguration(body);

  const connectorKey = requiredString(
    body.connectorKey,
    "connectorKey"
  );
  const externalSystem = requiredString(
    body.externalSystem,
    "externalSystem"
  );
  const connectorType = requiredString(
    body.connectorType,
    "connectorType"
  );

  const credential = generateConnectorCredential();

  try {
    const connector = await ConnectorConfig.create({
      clinicId: s(clinicId),
      connectorKey,
      externalSystem,
      connectorType,
      displayName: s(body.displayName),
      enabled: hasOwn(body, "enabled")
        ? requireBoolean(body.enabled, "enabled")
        : true,
      credentialKeyId: credential.credentialKeyId,
      credentialHash: credential.credentialHash,
      credentialVersion: credential.credentialVersion,
      configuration: {},
      createdBy: s(actorUserId),
      updatedBy: s(actorUserId),
    });

    return {
      connector: connectorView(connector),
      credential: {
        token: credential.token,
        credentialKeyId: credential.credentialKeyId,
        credentialVersion: credential.credentialVersion,
        shownOnce: true,
      },
    };
  } catch (err) {
    return duplicateCode(err, {
      code: "CONNECTOR_ALREADY_EXISTS",
      message:
        "Connector key or credential key already exists",
    });
  }
}

async function updateConnector({
  clinicId,
  connectorId,
  actorUserId,
  input,
}) {
  const body =
    input && typeof input === "object" ? input : {};

  assertServerOwnedClinic(body);
  assertConnectorCredentialFieldsNotSupplied(body);
  assertNoPlainConfiguration(body);

  for (const field of [
    "connectorKey",
    "externalSystem",
    "connectorType",
  ]) {
    if (hasOwn(body, field)) {
      throw codedError(
        `${field} is immutable`,
        "CONNECTOR_IDENTITY_IMMUTABLE",
        400,
        { field }
      );
    }
  }

  const connector = await resolveConnectorForClinic({
    clinicId,
    connectorId,
  });

  let changed = false;

  if (hasOwn(body, "displayName")) {
    connector.displayName = s(body.displayName);
    changed = true;
  }

  if (hasOwn(body, "enabled")) {
    connector.enabled = requireBoolean(
      body.enabled,
      "enabled"
    );
    changed = true;
  }

  if (!changed) {
    throw codedError(
      "No supported connector fields supplied",
      "NO_SUPPORTED_FIELDS",
      400
    );
  }

  connector.updatedBy = s(actorUserId);
  await connector.save();

  return connectorView(connector);
}

async function rotateConnectorCredential({
  clinicId,
  connectorId,
  actorUserId,
}) {
  const connector = await resolveConnectorForClinic({
    clinicId,
    connectorId,
  });

  const nextVersion =
    Number(connector.credentialVersion || 0) + 1;

  const credential = generateConnectorCredential({
    credentialVersion: nextVersion,
  });

  connector.credentialKeyId = credential.credentialKeyId;
  connector.credentialHash = credential.credentialHash;
  connector.credentialVersion =
    credential.credentialVersion;
  connector.updatedBy = s(actorUserId);

  try {
    await connector.save();
  } catch (err) {
    return duplicateCode(err, {
      code: "CREDENTIAL_KEY_CONFLICT",
      message:
        "Generated credential key conflicts with an existing connector",
    });
  }

  return {
    connector: connectorView(connector),
    credential: {
      token: credential.token,
      credentialKeyId: credential.credentialKeyId,
      credentialVersion: credential.credentialVersion,
      shownOnce: true,
    },
  };
}

async function listMappings({
  clinicId,
  connectorId,
}) {
  const connector = await resolveConnectorForClinic({
    clinicId,
    connectorId,
  });

  return InventoryItemMapping.find({
    clinicId: s(clinicId),
    connectorId: connector._id,
  })
    .populate(
      "stockItemId",
      "name sku unit active"
    )
    .sort({ createdAt: 1 })
    .lean();
}

async function createMapping({
  clinicId,
  connectorId,
  actorUserId,
  input,
}) {
  const body =
    input && typeof input === "object" ? input : {};

  assertServerOwnedClinic(body);

  if (hasOwn(body, "connectorId")) {
    throw codedError(
      "connectorId is path-owned",
      "CONNECTOR_SCOPE_PATH_OWNED",
      400
    );
  }

  if (hasOwn(body, "inventoryUnit")) {
    throw codedError(
      "inventoryUnit is derived from StockItem",
      "MAPPING_INVENTORY_UNIT_SERVER_OWNED",
      400
    );
  }

  const connector = await resolveConnectorForClinic({
    clinicId,
    connectorId,
  });

  const externalItemId = requiredString(
    body.externalItemId,
    "externalItemId"
  );
  const externalUnit = requiredString(
    body.externalUnit,
    "externalUnit"
  );

  const item = await resolveStockItemForClinic({
    clinicId,
    stockItemId: body.stockItemId,
  });

  const numerator = positiveSafeInteger(
    body.conversionNumerator,
    "conversionNumerator",
    1
  );
  const denominator = positiveSafeInteger(
    body.conversionDenominator,
    "conversionDenominator",
    1
  );

  try {
    const mapping = await InventoryItemMapping.create({
      clinicId: s(clinicId),
      connectorId: connector._id,
      externalItemId,
      externalUnit,
      stockItemId: item._id,
      inventoryUnit: s(item.unit),
      conversionNumerator: numerator,
      conversionDenominator: denominator,
      active: hasOwn(body, "active")
        ? requireBoolean(body.active, "active")
        : true,
      createdBy: s(actorUserId),
      updatedBy: s(actorUserId),
    });

    return mappingView(mapping);
  } catch (err) {
    return duplicateCode(err, {
      code: "ITEM_MAPPING_ALREADY_EXISTS",
      message: "Exact item mapping already exists",
    });
  }
}

async function updateMapping({
  clinicId,
  mappingId,
  actorUserId,
  input,
}) {
  const body =
    input && typeof input === "object" ? input : {};

  assertServerOwnedClinic(body);

  for (const field of [
    "connectorId",
    "externalItemId",
    "externalUnit",
    "inventoryUnit",
  ]) {
    if (hasOwn(body, field)) {
      throw codedError(
        `${field} is immutable or server-owned`,
        "MAPPING_IDENTITY_IMMUTABLE",
        400,
        { field }
      );
    }
  }

  const id = objectId(mappingId, "mappingId");

  const mapping = await InventoryItemMapping.findOne({
    _id: id,
    clinicId: s(clinicId),
  });

  if (!mapping) {
    throw codedError(
      "Item mapping not found",
      "ITEM_MAPPING_NOT_FOUND",
      404
    );
  }

  let changed = false;

  if (hasOwn(body, "stockItemId")) {
    const item = await resolveStockItemForClinic({
      clinicId,
      stockItemId: body.stockItemId,
    });

    mapping.stockItemId = item._id;
    mapping.inventoryUnit = s(item.unit);
    changed = true;
  }

  if (hasOwn(body, "conversionNumerator")) {
    mapping.conversionNumerator = positiveSafeInteger(
      body.conversionNumerator,
      "conversionNumerator"
    );
    changed = true;
  }

  if (hasOwn(body, "conversionDenominator")) {
    mapping.conversionDenominator = positiveSafeInteger(
      body.conversionDenominator,
      "conversionDenominator"
    );
    changed = true;
  }

  if (hasOwn(body, "active")) {
    mapping.active = requireBoolean(
      body.active,
      "active"
    );
    changed = true;
  }

  if (!changed) {
    throw codedError(
      "No supported mapping fields supplied",
      "NO_SUPPORTED_FIELDS",
      400
    );
  }

  mapping.updatedBy = s(actorUserId);
  await mapping.save();

  return mappingView(mapping);
}

module.exports = {
  listConnectors,
  createConnector,
  updateConnector,
  rotateConnectorCredential,
  listMappings,
  createMapping,
  updateMapping,
};
