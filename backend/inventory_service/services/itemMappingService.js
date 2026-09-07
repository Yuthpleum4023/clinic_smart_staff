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

module.exports = {
  assertMappingUnits,
  convertMappedQuantity,
};
