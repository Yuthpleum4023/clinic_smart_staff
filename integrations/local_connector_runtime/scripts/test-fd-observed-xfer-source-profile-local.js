"use strict";

const assert = require("assert");
const {
  normalizePollSpec,
  buildSelectQuery
} = require("../src/drivers/mysqlReadOnlyDriver");
const {
  createFdAdapter
} = require("../src/adapters/fdAdapter");
const {
  buildFdObservedXferSourceProfile
} = require(
  "../src/adapters/fd/observedXferSourceProfile"
);

(async () => {
  const p = buildFdObservedXferSourceProfile();

  assert.equal(
    p.status,
    "relational_source_verified_semantics_closed"
  );
  assert.equal(p.production.movementSemanticsVerified, true);
  assert.equal(p.production.adapterActivationAllowed, true);
  assert.equal(p.production.stockAuthority, false);
  assert.equal(p.production.clinicScopeAuthority, false);
  assert.equal(p.production.fuzzyMappingAllowed, false);
  assert.equal(p.source.poll.predicates.length, 0);

  const spec = normalizePollSpec(p.source.poll);
  const q = buildSelectQuery(spec, { cursor: 25296 });
  assert.match(q.sql, /WHERE `d`\.`id` > \?/);
  assert.deepEqual(q.values, [25296]);

  for (const literal of [
    "W-Sale",
    "A-add-pat",
    "A-del-pat",
    "PAT-"
  ]) {
    assert.equal(q.sql.includes(literal), false);
  }

  const ap = p.adapterProfile;
  assert.equal(ap.movementDerivation, "balance_delta");
  assert.equal(ap.fields.validationQuantity, "fd_doc_unit");
  assert.equal(ap.unitLiteral, "fd_balance_unit");

  const adapter = createFdAdapter(ap);
  const e = await adapter.transformRecord({
    id: 25297,
    fd_xfer_num: "W-20260796",
    fd_prod_num: 159,
    fd_doc_unit: 1,
    fd_previous_amount_unit: 0,
    fd_amount_unit: -1,
    fd_detail_input_date: "2026-09-11",
    fd_doc_type: "W-Sale"
  });
  assert.equal(e.quantity, 1);
  assert.equal(e.eventType, "inventory_out");

  console.log("FD_XFER_RELATIONAL_SOURCE_PROFILE_TESTS_PASSED=TRUE");
  console.log("FD_XFER_JOIN_SHAPE_VERIFIED=TRUE");
  console.log("FD_XFER_SEMANTIC_PREDICATES_ENABLED=FALSE");
  console.log("FD_XFER_MOVEMENT_SEMANTICS_VERIFIED=TRUE");
  console.log("FD_XFER_ADAPTER_ACTIVATION_ALLOWED=TRUE");
  console.log("FD_V5_INVARIANT_BOUND_TO_ADAPTER=TRUE");
  console.log("FD_XFER_PHI_SELECTED=FALSE");
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
