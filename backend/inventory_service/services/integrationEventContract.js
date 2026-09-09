const crypto = require("crypto");

const {
  positiveQty,
} = require("../utils/quantity");

const {
  s,
  lower,
} = require("../utils/strings");

const CONTRACT_VERSION = 1;

// Additive v1 event-type expansion.
// Existing "dispensed" payload semantics remain unchanged.
const SUPPORTED_EVENT_TYPES = new Set([
  "dispensed",
  "inventory_in",
  "inventory_out",
]);

function bad(message, code) {
  const err = new Error(message);
  err.status = 400;
  err.code = code;
  return err;
}

function requiredString(
  value,
  label,
  code
) {
  const out = s(value);

  if (!out) {
    throw bad(
      `${label} is required`,
      code
    );
  }

  return out;
}

function requiredDate(
  value,
  label = "occurredAt"
) {
  if (
    value === null ||
    value === undefined ||
    s(value) === ""
  ) {
    throw bad(
      `${label} is required`,
      "OCCURRED_AT_REQUIRED"
    );
  }

  const date =
    value instanceof Date
      ? value
      : new Date(value);

  if (Number.isNaN(date.getTime())) {
    throw bad(
      `${label} must be a valid date`,
      "INVALID_OCCURRED_AT"
    );
  }

  return date;
}

function normalizeMetadata(value) {
  if (
    value === null ||
    value === undefined
  ) {
    return {};
  }

  if (
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw bad(
      "metadata must be an object",
      "INVALID_METADATA"
    );
  }

  return value;
}

function canonicalPayload(normalized) {
  return {
    contractVersion:
      CONTRACT_VERSION,
    externalEventId:
      normalized.externalEventId,
    externalLineId:
      normalized.externalLineId,
    externalItemId:
      normalized.externalItemId,
    externalUnit:
      normalized.externalUnit,
    externalQuantity:
      normalized.externalQuantity,
    eventType:
      normalized.eventType,
    occurredAt:
      normalized.occurredAt
        .toISOString(),
    referenceType:
      normalized.referenceType,
    referenceNo:
      normalized.referenceNo,
  };
}

function payloadHash(normalized) {
  return crypto
    .createHash("sha256")
    .update(
      JSON.stringify(
        canonicalPayload(normalized)
      )
    )
    .digest("hex");
}

function normalizeMovementEvent(
  input = {}
) {
  const externalEventId =
    requiredString(
      input.externalEventId,
      "externalEventId",
      "EXTERNAL_EVENT_ID_REQUIRED"
    );

  const externalLineId =
    s(input.externalLineId) || "0";

  const externalItemId =
    requiredString(
      input.externalItemId,
      "externalItemId",
      "EXTERNAL_ITEM_ID_REQUIRED"
    );

  const externalUnit =
    requiredString(
      input.unit ??
        input.externalUnit,
      "unit",
      "EXTERNAL_UNIT_REQUIRED"
    );

  const externalQuantity =
    positiveQty(
      input.quantity ??
        input.externalQuantity,
      "quantity"
    );

  const eventType =
    lower(
      requiredString(
        input.eventType,
        "eventType",
        "EVENT_TYPE_REQUIRED"
      )
    );

  if (
    !SUPPORTED_EVENT_TYPES
      .has(eventType)
  ) {
    throw bad(
      `Unsupported eventType: ${eventType}`,
      "UNSUPPORTED_EVENT_TYPE"
    );
  }

  const occurredAt =
    requiredDate(
      input.occurredAt
    );

  const normalized = {
    externalEventId,
    externalLineId,
    externalItemId,
    externalUnit,
    externalQuantity,
    eventType,
    occurredAt,

    referenceType:
      s(input.referenceType),

    referenceNo:
      s(input.referenceNo),

    metadata:
      normalizeMetadata(
        input.metadata
      ),
  };

  return {
    ...normalized,
    payloadHash:
      payloadHash(normalized),
  };
}

// Backward-compatible function name. The v1 payload
// shape is unchanged; event-type support is additive.
function normalizeConsumptionEvent(
  input = {}
) {
  return normalizeMovementEvent(input);
}

module.exports = {
  CONTRACT_VERSION,
  SUPPORTED_EVENT_TYPES,
  canonicalPayload,
  payloadHash,
  normalizeMovementEvent,
  normalizeConsumptionEvent,
};
