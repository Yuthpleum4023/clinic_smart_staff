"use strict";

const assert = require("assert");

const {
  createFdAdapter
} = require("../src/adapters/fdAdapter");

const {
  FD_OBSERVED_XFER_SOURCE_PROFILE
} = require(
  "../src/adapters/fd/observedXferSourceProfile"
);

(async () => {
  const adapter = createFdAdapter(
    FD_OBSERVED_XFER_SOURCE_PROFILE
      .adapterProfile
  );

  const base = {
    fd_prod_num: 213,
    fd_doc_unit: 1,
    fd_previous_amount_unit: 0,
    fd_detail_input_date:
      "2026-09-18",
    fd_from_locat: "R08",
    fd_to_locat: "PAT-1756"
  };

  const dispense =
    await adapter.transformRecord({
      ...base,
      id: 25319,
      fd_xfer_num: "fixture-dispense-1",
      fd_amount_unit: -1,
      fd_doc_type: "W-Sale"
    });

  assert.equal(
    dispense.eventType,
    "dispensed"
  );
  assert.equal(dispense.quantity, 1);

  const reversal =
    await adapter.transformRecord({
      ...base,
      id: 25320,
      fd_xfer_num: "fixture-reversal-1",
      fd_amount_unit: 1,
      fd_doc_type: "A-add-pat"
    });

  assert.equal(
    reversal.eventType,
    "reversal"
  );
  assert.equal(reversal.quantity, 1);

  const redispense =
    await adapter.transformRecord({
      ...base,
      id: 25321,
      fd_xfer_num: "fixture-dispense-2",
      fd_amount_unit: -1,
      fd_doc_type: "W-Sale"
    });

  assert.equal(
    redispense.eventType,
    "dispensed"
  );

  const unrelatedInbound =
    await adapter.transformRecord({
      ...base,
      id: 25322,
      fd_xfer_num: "fixture-unverified-in",
      fd_amount_unit: 1,
      fd_doc_type:
        "UNVERIFIED-INVENTORY-MOVEMENT"
    });

  assert.equal(
    unrelatedInbound,
    null
  );

  await assert.rejects(
    () =>
      adapter.transformRecord({
        ...base,
        id: 25323,
        fd_xfer_num:
          "fixture-direction-violation",
        fd_amount_unit: 1,
        fd_doc_type: "W-Sale"
      }),
    /FD_BALANCE_DELTA_DIRECTION_CONTRACT_VIOLATION/
  );

  console.log(
    "FD_PATIENT_MOVEMENT_SEMANTICS_TESTS_PASSED=TRUE"
  );
  console.log(
    "FD_UNVERIFIED_STOCK_AUTHORITY_BLOCKED=TRUE"
  );
  console.log(
    "FD_REVERSAL_DISTINCT_FROM_STOCK_IN=TRUE"
  );
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
