const InventoryItemMapping = require("../models/InventoryItemMapping");
const StockItem = require("../models/StockItem");

const {
  positiveQty,
} = require("../utils/quantity");

const {
  s,
} = require("../utils/strings");

function contractError(
  message,
  code,
  status = 409
) {
  const err = new Error(message);
  err.status = status;
  err.code = code;
  return err;
}

function positiveSafeInteger(
  value,
  label
) {
  const n = Number(value);

  if (
    !Number.isSafeInteger(n) ||
    n <= 0
  ) {
    throw contractError(
      `${label} must be a positive safe integer`,
      "INVALID_CONVERSION_FACTOR",
      400
    );
  }

  return n;
}

function assertMappingUnits({
  eventExternalUnit,
  mappingExternalUnit,
  stockItemUnit,
  mappingInventoryUnit,
}) {
  if (
    s(eventExternalUnit) !==
    s(mappingExternalUnit)
  ) {
    throw contractError(
      "External unit does not match mapping",
      "MAPPING_EXTERNAL_UNIT_MISMATCH"
    );
  }

  if (
    s(stockItemUnit) !==
    s(mappingInventoryUnit)
  ) {
    throw contractError(
      "Inventory item unit no longer matches mapping",
      "MAPPING_INVENTORY_UNIT_MISMATCH"
    );
  }
}

function convertMappedQuantity({
  externalQuantity,
  conversionNumerator = 1,
  conversionDenominator = 1,
}) {
  const quantity =
    positiveQty(
      externalQuantity,
      "externalQuantity"
    );

  const numerator =
    positiveSafeInteger(
      conversionNumerator,
      "conversionNumerator"
    );

  const denominator =
    positiveSafeInteger(
      conversionDenominator,
      "conversionDenominator"
    );

  return positiveQty(
    (quantity * numerator) /
      denominator,
    "normalizedQuantity"
  );
}

function withSession(query, session) {
  return session
    ? query.session(session)
    : query;
}

async function resolveMappedInventoryItem({
  clinicId,
  connectorId,
  externalItemId,
  externalUnit,
  session = null,
}) {
  const mappingQuery =
    InventoryItemMapping.findOne({
      clinicId: s(clinicId),
      connectorId,
      externalItemId: s(externalItemId),
      externalUnit: s(externalUnit),
      active: true,
    });

  const mapping =
    await withSession(
      mappingQuery,
      session
    );

  if (!mapping) {
    throw contractError(
      "Inventory item mapping not found",
      "ITEM_MAPPING_NOT_FOUND"
    );
  }

  const itemQuery =
    StockItem.findOne({
      _id: mapping.stockItemId,
      clinicId: s(clinicId),
    });

  const item =
    await withSession(
      itemQuery,
      session
    );

  if (!item) {
    throw contractError(
      "Mapped stock item not found in connector clinic",
      "MAPPED_STOCK_ITEM_NOT_FOUND"
    );
  }

  if (!item.active) {
    throw contractError(
      "Mapped stock item is inactive",
      "STOCK_ITEM_INACTIVE"
    );
  }

  assertMappingUnits({
    eventExternalUnit:
      externalUnit,
    mappingExternalUnit:
      mapping.externalUnit,
    stockItemUnit:
      item.unit,
    mappingInventoryUnit:
      mapping.inventoryUnit,
  });

  return {
    mapping,
    item,
  };
}

module.exports = {
  assertMappingUnits,
  convertMappedQuantity,
  resolveMappedInventoryItem,
};
