"use strict";

const assert = require("assert");
const {
  createFdAdapter,
} = require("../src/adapters/fdAdapter");

(async () => {
  const balanceAdapter = createFdAdapter({
    schemaVerified: true,
    movementSemanticsVerified: true,
    movementDerivation: "balance_delta",
    sourceName: "fixture_balance",
    unitLiteral: "piece",
    fields: {
      eventId: "event_id",
      itemId: "item_id",
      previousAmountUnit: "previous_qty",
      amountUnit: "current_qty",
      occurredAt: "occurred_at",
    },
  });

  const out = await balanceAdapter.transformRecord({
    event_id: "B-1",
    item_id: "P-1",
    previous_qty: 10,
    current_qty: 8,
    occurred_at: "2026-09-10T00:00:00Z",
  });

  assert.equal(out.quantity, 2);
  assert.equal(out.eventType, "inventory_out");
  assert.equal(
    out.metadata.movementDerivation,
    "balance_delta"
  );

  const directAdapter = createFdAdapter({
    schemaVerified: true,
    movementSemanticsVerified: true,
    movementDerivation: "direct_quantity",
    eventTypeLiteral: "dispensed",
    sourceName: "fixture_direct",
    fields: {
      eventId: "event_id",
      itemId: "item_id",
      quantity: "qty",
      unit: "unit",
      occurredAt: "occurred_at",
    },
  });

  const direct = await directAdapter.transformRecord({
    event_id: "D-1",
    item_id: "P-2",
    qty: 3,
    unit: "piece",
    occurred_at: "2026-09-10T01:00:00Z",
  });

  assert.equal(direct.quantity, 3);
  assert.equal(direct.eventType, "dispensed");
  assert.equal(
    direct.metadata.movementDerivation,
    "direct_quantity"
  );

  assert.equal("clinicId" in direct, false);
  assert.equal("stockItemId" in direct, false);

  await assert.rejects(
    () =>
      directAdapter.transformRecord({
        event_id: "D-2",
        item_id: "P-2",
        qty: 0,
        unit: "piece",
        occurred_at: "2026-09-10T01:00:00Z",
      }),
    /FD_QUANTITY_VALUE_REQUIRED/
  );

  assert.throws(
    () =>
      createFdAdapter({
        schemaVerified: true,
        movementSemanticsVerified: true,
        movementDerivation: "direct_quantity",
        eventTypeLiteral: "",
        fields: {
          eventId: "event_id",
          itemId: "item_id",
          quantity: "qty",
          unit: "unit",
          occurredAt: "occurred_at",
        },
      }),
    /FD_DIRECT_EVENT_TYPE_REQUIRED/
  );

  console.log(
    "FD_DERIVATION_STRATEGY_TESTS_PASSED=TRUE"
  );
})().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
