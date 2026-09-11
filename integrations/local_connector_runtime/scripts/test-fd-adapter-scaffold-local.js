"use strict";

const assert = require("assert");
const {
  createFdAdapter
} = require("../src/adapters/fdAdapter");

(async () => {
  const adapter = createFdAdapter({
    schemaVerified: true,
    movementSemanticsVerified: true,
    movementDerivation: "balance_delta",
    sourceName: "fd_xfer",
    unitLiteral: "fd_balance_unit",
    fields: {
      eventId: "id",
      lineId: "",
      itemId: "prod",
      previousAmountUnit: "prv",
      amountUnit: "amt",
      validationQuantity: "doc",
      quantity: "",
      unit: "",
      occurredAt: "at",
      referenceNo: "ref",
      referenceType: "doctype"
    }
  });

  const base = {
    prod: 159,
    at: "2026-09-11",
    ref: "W-20260796"
  };

  const out = await adapter.transformRecord({
    ...base,
    id: 25297,
    prv: 0,
    amt: -1,
    doc: 1,
    doctype: "W-Sale"
  });
  assert.equal(out.quantity, 1);
  assert.equal(out.eventType, "inventory_out");
  assert.equal(out.unit, "fd_balance_unit");

  const inbound = await adapter.transformRecord({
    ...base,
    id: 25275,
    prv: 0,
    amt: 1,
    doc: 1,
    doctype: "A-add-pat"
  });
  assert.equal(inbound.quantity, 1);
  assert.equal(inbound.eventType, "inventory_in");

  const directionIgnoresDocType =
    await adapter.transformRecord({
      ...base,
      id: 30001,
      prv: 10,
      amt: 12,
      doc: 2,
      doctype: "W-Sale"
    });
  assert.equal(directionIgnoresDocType.eventType, "inventory_in");

  await assert.rejects(
    () =>
      adapter.transformRecord({
        ...base,
        id: 30002,
        prv: 10,
        amt: 8,
        doc: 1,
        doctype: "anything"
      }),
    /FD_MOVEMENT_MAGNITUDE_INVARIANT_VIOLATION/
  );

  const zero = await adapter.transformRecord({
    ...base,
    id: 30003,
    prv: 5,
    amt: 5,
    doc: 0,
    doctype: "anything"
  });
  assert.equal(zero, null);

  for (const e of [out, inbound]) {
    for (const key of [
      "clinicId",
      "connectorId",
      "stockItemId",
      "mappingId",
      "currentStock",
      "balanceBefore",
      "balanceAfter",
      "normalizedQuantity"
    ]) {
      assert.equal(key in e, false);
    }
  }

  console.log("FD_ADAPTER_MOVEMENT_TESTS_PASSED=TRUE");
  console.log("FD_V5_MAGNITUDE_INVARIANT_ENFORCED=TRUE");
  console.log("FD_DIRECTION_DERIVATION=AMOUNT_UNIT_DELTA");
  console.log("FD_DOCTYPE_USED_FOR_DIRECTION=FALSE");
  console.log("FD_STATUS_USED_FOR_DIRECTION=FALSE");
  console.log("FD_STOCK_AUTHORITY=FALSE");
  console.log("FD_CLINIC_SCOPE_AUTHORITY=FALSE");
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
