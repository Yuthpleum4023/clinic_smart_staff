"use strict";

const assert = require("assert");
const path = require("path");

const {
  buildNormalizedMovementEvent,
  buildNormalizedConsumptionEvent
} = require(
  "../src/core/normalizedEvent"
);

const backendContract = require(
  path.resolve(
    __dirname,
    "../../../backend/inventory_service/services/integrationEventContract.js"
  )
);

function assertCompatible(event) {
  const normalized =
    backendContract
      .normalizeMovementEvent(
        event
      );

  assert.equal(
    normalized.externalEventId,
    event.externalEventId
  );
  assert.equal(
    normalized.externalLineId,
    event.externalLineId
  );
  assert.equal(
    normalized.externalItemId,
    event.externalItemId
  );
  assert.equal(
    normalized.externalUnit,
    event.unit
  );
  assert.equal(
    normalized.externalQuantity,
    event.quantity
  );
  assert.equal(
    normalized.eventType,
    event.eventType
  );
  assert.equal(
    normalized.occurredAt
      .toISOString(),
    event.occurredAt
  );
  assert.equal(
    backendContract.CONTRACT_VERSION,
    event.contractVersion
  );
}

const legacy =
  buildNormalizedConsumptionEvent({
    externalEventId:
      "compat-legacy",
    externalLineId: "1",
    externalItemId:
      "compat-item",
    unit: "piece",
    quantity: 3,
    eventType: "dispensed",
    occurredAt:
      "2026-09-08T02:00:00Z",
    referenceType:
      "dispense",
    referenceNo: "R-1"
  });

const inbound =
  buildNormalizedMovementEvent({
    externalEventId:
      "compat-in",
    externalLineId: "2",
    externalItemId:
      "compat-item",
    unit: "piece",
    quantity: 4,
    eventType:
      "inventory_in",
    occurredAt:
      "2026-09-08T03:00:00Z"
  });

const outbound =
  buildNormalizedMovementEvent({
    externalEventId:
      "compat-out",
    externalLineId: "3",
    externalItemId:
      "compat-item",
    unit: "piece",
    quantity: 2,
    eventType:
      "inventory_out",
    occurredAt:
      "2026-09-08T04:00:00Z"
  });

for (const event of [
  legacy,
  inbound,
  outbound
]) {
  assertCompatible(event);
}

assert.equal(
  backendContract
    .normalizeConsumptionEvent(
      legacy
    ).eventType,
  "dispensed"
);

console.log(
  "BACKEND_CONTRACT_COMPATIBILITY=PASS"
);
console.log(
  `CONTRACT_VERSION=${backendContract.CONTRACT_VERSION}`
);
console.log(
  "LEGACY_DISPENSED_COMPATIBILITY=PASS"
);
console.log(
  "BIDIRECTIONAL_MOVEMENT_EVENT_TYPES=PASS"
);
console.log(
  "VENDOR_NEUTRAL_EVENT_SHAPE=PASS"
);
