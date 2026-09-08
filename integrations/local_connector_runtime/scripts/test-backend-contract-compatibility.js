"use strict";

const assert = require("assert");
const path = require("path");

const {
  buildNormalizedConsumptionEvent
} = require("../src/core/normalizedEvent");

const backendContract = require(
  path.resolve(
    __dirname,
    "../../../backend/inventory_service/services/integrationEventContract.js"
  )
);

const event = buildNormalizedConsumptionEvent({
  externalEventId: "compat-event",
  externalLineId: "7",
  externalItemId: "compat-item",
  unit: "piece",
  quantity: 3,
  eventType: "dispensed",
  occurredAt: "2026-09-08T02:00:00Z",
  referenceType: "dispense",
  referenceNo: "R-1"
});

const normalized = backendContract.normalizeConsumptionEvent(event);

assert.equal(normalized.externalEventId, event.externalEventId);
assert.equal(normalized.externalLineId, event.externalLineId);
assert.equal(normalized.externalItemId, event.externalItemId);
assert.equal(normalized.externalUnit, event.unit);
assert.equal(normalized.externalQuantity, event.quantity);
assert.equal(normalized.eventType, event.eventType);
assert.equal(normalized.occurredAt.toISOString(), event.occurredAt);
assert.equal(backendContract.CONTRACT_VERSION, event.contractVersion);

console.log("BACKEND_CONTRACT_COMPATIBILITY=PASS");
console.log(`CONTRACT_VERSION=${backendContract.CONTRACT_VERSION}`);
console.log("VENDOR_NEUTRAL_EVENT_SHAPE=PASS");
