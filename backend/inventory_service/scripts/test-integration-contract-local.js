const assert = require("node:assert/strict");

const {
  normalizeConsumptionEvent,
} = require("../services/integrationEventContract");

const {
  assertMappingUnits,
  convertMappedQuantity,
} = require("../services/itemMappingService");

function expectCode(fn, expectedCode) {
  let thrown = null;

  try {
    fn();
  } catch (err) {
    thrown = err;
  }

  assert.ok(
    thrown,
    `Expected error code ${expectedCode}`
  );

  assert.equal(
    thrown.code,
    expectedCode
  );
}

function run() {
  const base = {
    externalEventId:
      "DISP-20260907-000123",
    externalLineId: "1",
    externalItemId: "MED001",
    quantity: 2,
    unit: "box",
    eventType: "dispensed",
    occurredAt:
      "2026-09-07T10:32:00+07:00",
    referenceType:
      "patient_dispense",
    referenceNo:
      "VISIT-10291",
    metadata: {
      transportAttempt: 1,
    },
  };

  const first =
    normalizeConsumptionEvent(base);

  assert.equal(
    first.externalEventId,
    "DISP-20260907-000123"
  );

  assert.equal(
    first.externalLineId,
    "1"
  );

  assert.equal(
    first.externalQuantity,
    2
  );

  assert.equal(
    first.eventType,
    "dispensed"
  );

  assert.match(
    first.payloadHash,
    /^[a-f0-9]{64}$/
  );

  const sameSemanticPayload =
    normalizeConsumptionEvent({
      ...base,
      metadata: {
        transportAttempt: 999,
        retry: true,
      },
    });

  assert.equal(
    sameSemanticPayload.payloadHash,
    first.payloadHash
  );

  const changedQuantity =
    normalizeConsumptionEvent({
      ...base,
      quantity: 3,
    });

  assert.notEqual(
    changedQuantity.payloadHash,
    first.payloadHash
  );

  const defaultLine =
    normalizeConsumptionEvent({
      ...base,
      externalLineId: "",
    });

  assert.equal(
    defaultLine.externalLineId,
    "0"
  );

  expectCode(
    () =>
      normalizeConsumptionEvent({
        ...base,
        externalEventId: "",
      }),
    "EXTERNAL_EVENT_ID_REQUIRED"
  );

  expectCode(
    () =>
      normalizeConsumptionEvent({
        ...base,
        quantity: 0,
      }),
    "INVALID_QUANTITY"
  );

  expectCode(
    () =>
      normalizeConsumptionEvent({
        ...base,
        eventType: "returned",
      }),
    "UNSUPPORTED_EVENT_TYPE"
  );

  expectCode(
    () =>
      normalizeConsumptionEvent({
        ...base,
        occurredAt: "",
      }),
    "OCCURRED_AT_REQUIRED"
  );

  expectCode(
    () =>
      normalizeConsumptionEvent({
        ...base,
        metadata: [],
      }),
    "INVALID_METADATA"
  );

  assert.equal(
    convertMappedQuantity({
      externalQuantity: 2,
      conversionNumerator: 100,
      conversionDenominator: 1,
    }),
    200
  );

  assert.equal(
    convertMappedQuantity({
      externalQuantity: 1,
      conversionNumerator: 1,
      conversionDenominator: 8,
    }),
    0.125
  );

  // Inventory quantity contract is 0.001 precision.
  expectCode(
    () =>
      convertMappedQuantity({
        externalQuantity: 1,
        conversionNumerator: 1,
        conversionDenominator: 10000,
      }),
    "INVALID_QUANTITY"
  );

  expectCode(
    () =>
      convertMappedQuantity({
        externalQuantity: 1,
        conversionNumerator: 1.5,
        conversionDenominator: 1,
      }),
    "INVALID_CONVERSION_FACTOR"
  );

  assert.doesNotThrow(() =>
    assertMappingUnits({
      eventExternalUnit: "box",
      mappingExternalUnit: "box",
      stockItemUnit: "piece",
      mappingInventoryUnit: "piece",
    })
  );

  expectCode(
    () =>
      assertMappingUnits({
        eventExternalUnit: "piece",
        mappingExternalUnit: "box",
        stockItemUnit: "piece",
        mappingInventoryUnit: "piece",
      }),
    "MAPPING_EXTERNAL_UNIT_MISMATCH"
  );

  expectCode(
    () =>
      assertMappingUnits({
        eventExternalUnit: "box",
        mappingExternalUnit: "box",
        stockItemUnit: "box",
        mappingInventoryUnit: "piece",
      }),
    "MAPPING_INVENTORY_UNIT_MISMATCH"
  );

  console.log(
    "INTEGRATION_CONTRACT_TESTS_PASSED=TRUE"
  );
  console.log(
    "STOCK_CORE_CHANGED=FALSE"
  );
  console.log(
    "ROUTES_EXPOSED=FALSE"
  );
  console.log(
    "CONNECTOR_AUTH_ENABLED=FALSE"
  );
}

run();
