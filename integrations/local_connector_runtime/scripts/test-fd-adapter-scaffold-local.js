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
        movementSemanticsVerified:
          true,
        fields: {}
      }),
    /FD_SCHEMA_VERIFICATION_REQUIRED/
  );

  assert.throws(
    () =>
      createFdAdapter({
        schemaVerified: true,
        movementSemanticsVerified:
          false,
        fields: {}
      }),
    /FD_MOVEMENT_SEMANTICS_VERIFICATION_REQUIRED/
  );

  assert.throws(
    () =>
      requiredProfile({
        schemaVerified: true,
        movementSemanticsVerified:
          true,
        unitLiteral:
          "fd_amount_unit",
        fields: {
          eventId: "",
          itemId: "",
          previousAmountUnit: "",
          amountUnit: "",
          occurredAt: ""
        }
      }),
    /_REQUIRED/
  );

  const profile = {
    schemaVerified: true,
    movementSemanticsVerified:
      true,
    sourceName: "fd",
    unitLiteral:
      "fd_amount_unit",
    fields: {
      eventId: "verified_event_key",
      lineId: "verified_line_key",
      itemId: "verified_item_key",
      previousAmountUnit:
        "verified_previous_amount",
      amountUnit:
        "verified_amount",
      unit: "",
      occurredAt: "verified_time",
      referenceNo: "verified_ref",
      referenceType:
        "verified_reference_type"
    }
  };

  const adapter =
    createFdAdapter(profile);

  const baseRow = {
    verified_event_key:
      "E-100",
    verified_line_key:
      "L-2",
    verified_item_key:
      "ITEM-X",
    verified_time:
      "2026-09-08T06:00:00Z",
    verified_ref:
      "R-100",
    verified_reference_type:
      "source-doc"
  };

  assert.equal(
    adapter.assertSourceRecord(
      baseRow
    ),
    true
  );

  const inbound =
    await adapter.transformRecord({
      ...baseRow,
      verified_previous_amount:
        4,
      verified_amount:
        7
    });

  assert.equal(
    inbound.externalEventId,
    "E-100"
  );

  assert.equal(
    inbound.externalLineId,
    "L-2"
  );

  assert.equal(
    inbound.externalItemId,
    "ITEM-X"
  );

  assert.equal(
    inbound.quantity,
    3
  );

  assert.equal(
    inbound.unit,
    "fd_amount_unit"
  );

  assert.equal(
    inbound.eventType,
    "inventory_in"
  );

  const outbound =
    await adapter.transformRecord({
      ...baseRow,
      verified_previous_amount:
        7,
      verified_amount:
        2
    });

  assert.equal(
    outbound.quantity,
    5
  );

  assert.equal(
    outbound.eventType,
    "inventory_out"
  );

  const zeroDelta =
    await adapter.transformRecord({
      ...baseRow,
      verified_previous_amount:
        2,
      verified_amount:
        2
    });

  assert.equal(
    zeroDelta,
    null
  );

  for (const event of [
    inbound,
    outbound
  ]) {
    for (const field of [
      "clinicId",
      "connectorId",
      "externalSystem",
      "stockItemId",
      "mappingId",
      "stockMovementId",
      "normalizedQuantity",
      "reprocess",
      "currentStock",
      "balanceBefore",
      "balanceAfter"
    ]) {
      assert.equal(
        Object.prototype
          .hasOwnProperty.call(
            event,
            field
          ),
        false
      );
    }
  }

  console.log(
    "FD_ADAPTER_MOVEMENT_TESTS_PASSED=TRUE"
  );
  console.log(
    "FD_SCHEMA_ASSUMPTIONS_ALLOWED=FALSE"
  );
  console.log(
    "FD_SCHEMA_VERIFICATION_REQUIRED=TRUE"
  );
  console.log(
    "FD_MOVEMENT_SEMANTICS_VERIFIED=TRUE"
  );
  console.log(
    "FD_DIRECTION_DERIVATION=AMOUNT_UNIT_DELTA"
  );
  console.log(
    "FD_DOCTYPE_USED_FOR_DIRECTION=FALSE"
  );
  console.log(
    "FD_ZERO_DELTA_MATERIALIZED=FALSE"
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
