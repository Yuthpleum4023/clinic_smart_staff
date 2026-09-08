"use strict";

const assert = require("assert");

const {
  requiredProfile,
  createFdAdapter
} = require(
  "../src/adapters/fdAdapter"
);

(async () => {
  assert.throws(
    () =>
      createFdAdapter({
        schemaVerified: false,
        fields: {}
      }),
    /FD_SCHEMA_VERIFICATION_REQUIRED/
  );

  assert.throws(
    () =>
      requiredProfile({
        schemaVerified: true,
        fields: {
          eventId: "",
          itemId: "",
          quantity: "",
          unit: "",
          occurredAt: ""
        }
      }),
    /_REQUIRED/
  );

  const profile = {
    schemaVerified: true,
    sourceName: "fd",
    fields: {
      eventId: "verified_event_key",
      lineId: "verified_line_key",
      itemId: "verified_item_key",
      quantity: "verified_qty",
      unit: "verified_unit",
      occurredAt: "verified_time",
      referenceNo: "verified_ref",
      referenceType: ""
    }
  };

  const adapter =
    createFdAdapter(profile);

  const row = {
    verified_event_key:
      "E-100",
    verified_line_key:
      "L-2",
    verified_item_key:
      "ITEM-X",
    verified_qty:
      3,
    verified_unit:
      "piece",
    verified_time:
      "2026-09-08T06:00:00Z",
    verified_ref:
      "R-100"
  };

  assert.equal(
    adapter.assertSourceRecord(row),
    true
  );

  const event =
    await adapter.transformRecord(row);

  assert.equal(
    event.externalEventId,
    "E-100"
  );

  assert.equal(
    event.externalLineId,
    "L-2"
  );

  assert.equal(
    event.externalItemId,
    "ITEM-X"
  );

  assert.equal(
    event.quantity,
    3
  );

  assert.equal(
    event.unit,
    "piece"
  );

  assert.equal(
    event.eventType,
    "dispensed"
  );

  for (const field of [
    "clinicId",
    "connectorId",
    "externalSystem",
    "stockItemId",
    "mappingId",
    "stockMovementId",
    "normalizedQuantity",
    "reprocess"
  ]) {
    assert.equal(
      Object.prototype.hasOwnProperty.call(
        event,
        field
      ),
      false
    );
  }

  console.log(
    "FD_ADAPTER_SCAFFOLD_TESTS_PASSED=TRUE"
  );
  console.log(
    "FD_SCHEMA_ASSUMPTIONS_ALLOWED=FALSE"
  );
  console.log(
    "FD_SCHEMA_VERIFICATION_REQUIRED=TRUE"
  );
  console.log(
    "FD_STOCK_AUTHORITY=FALSE"
  );
  console.log(
    "FD_CLINIC_SCOPE_AUTHORITY=FALSE"
  );
  console.log(
    "FD_FUZZY_MAPPING=FALSE"
  );
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
