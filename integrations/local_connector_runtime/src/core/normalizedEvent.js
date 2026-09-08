"use strict";

const CONTRACT_VERSION = 1;
const SUPPORTED_EVENT_TYPES = new Set(["dispensed"]);

function s(v) {
  return String(v ?? "").trim();
}

function fail(code, message) {
  const err = new Error(message);
  err.code = code;
  throw err;
}

function buildNormalizedConsumptionEvent(input = {}) {
  const externalEventId = s(input.externalEventId);
  const externalLineId = s(input.externalLineId) || "0";
  const externalItemId = s(input.externalItemId);
  const unit = s(input.unit ?? input.externalUnit);
  const quantity = Number(input.quantity ?? input.externalQuantity);
  const eventType = s(input.eventType).toLowerCase();
  const occurredAt = new Date(input.occurredAt);

  if (!externalEventId) fail("EXTERNAL_EVENT_ID_REQUIRED", "externalEventId is required");
  if (!externalItemId) fail("EXTERNAL_ITEM_ID_REQUIRED", "externalItemId is required");
  if (!unit) fail("EXTERNAL_UNIT_REQUIRED", "unit is required");
  if (!Number.isFinite(quantity) || quantity <= 0) fail("INVALID_QUANTITY", "quantity must be > 0");
  if (!SUPPORTED_EVENT_TYPES.has(eventType)) fail("UNSUPPORTED_EVENT_TYPE", `Unsupported eventType: ${eventType}`);
  if (Number.isNaN(occurredAt.getTime())) fail("INVALID_OCCURRED_AT", "occurredAt must be valid");

  const event = {
    contractVersion: CONTRACT_VERSION,
    externalEventId,
    externalLineId,
    externalItemId,
    unit,
    quantity,
    eventType,
    occurredAt: occurredAt.toISOString(),
    referenceType: s(input.referenceType),
    referenceNo: s(input.referenceNo),
    metadata:
      input.metadata && typeof input.metadata === "object" && !Array.isArray(input.metadata)
        ? { ...input.metadata }
        : {}
  };

  delete event.clinicId;
  delete event.connectorId;
  delete event.externalSystem;
  delete event.reprocess;

  return event;
}

module.exports = {
  CONTRACT_VERSION,
  SUPPORTED_EVENT_TYPES,
  buildNormalizedConsumptionEvent
};
