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
  FD_OBSERVED_XFER_SOURCE_PROFILE,
  buildFdObservedXferSourceProfile
} = require(
  "../src/adapters/fd/observedXferSourceProfile"
);

(() => {
  const profile =
    buildFdObservedXferSourceProfile();

  assert.equal(
    profile.status,
    "relational_source_candidate_semantics_unverified"
  );

  assert.equal(
    profile.production.schemaCoordinatesVerified,
    true
  );

  assert.equal(
    profile.production.relationalSourceShapeVerified,
    true
  );

  assert.equal(
    profile.production.movementSemanticsVerified,
    false
  );

  assert.equal(
    profile.production.adapterActivationAllowed,
    false
  );

  assert.equal(
    profile.production.stockAuthority,
    false
  );

  assert.equal(
    profile.production.clinicScopeAuthority,
    false
  );

  assert.equal(
    profile.source.poll.table,
    "xferdtl"
  );

  assert.equal(
    profile.source.poll.alias,
    "d"
  );

  assert.equal(
    profile.source.poll.joins.length,
    1
  );

  assert.equal(
    profile.source.poll.joins[0].table,
    "xferhdr"
  );

  assert.equal(
    profile.source.poll.joins[0].left.column,
    "XferNum"
  );

  assert.equal(
    profile.source.poll.joins[0].right.column,
    "XferNum"
  );

  assert.equal(
    profile.source.poll.predicates.length,
    0
  );

  assert.equal(
    profile.source.poll.cursorColumn,
    "id"
  );

  assert.equal(
    profile.source.poll.cursorTableAlias,
    "d"
  );

  const selectedSourceColumns =
    profile.source.poll.columns.map(
      (entry) =>
        `${entry.tableAlias}.${entry.column}`
    );

  for (const forbidden of [
    "PatNum",
    "PatientName",
    "FirstName",
    "LastName",
    "Phone",
    "Address"
  ]) {
    assert.equal(
      selectedSourceColumns.some(
        (value) =>
          value.toLowerCase().includes(
            forbidden.toLowerCase()
          )
      ),
      false
    );
  }

  const spec =
    normalizePollSpec(
      profile.source.poll
    );

  const query =
    buildSelectQuery(
      spec,
      { cursor: 25296 }
    );

  assert.match(
    query.sql,
    /FROM `FD5_5`\.`xferdtl` AS `d` INNER JOIN `FD5_5`\.`xferhdr` AS `h` ON `d`\.`XferNum` = `h`\.`XferNum`/
  );

  assert.match(
    query.sql,
    /WHERE `d`\.`id` > \?/
  );

  assert.deepEqual(
    query.values,
    [25296]
  );

  assert.equal(
    query.sql.includes("W-Sale"),
    false
  );

  assert.equal(
    query.sql.includes("PAT-"),
    false
  );

  assert.equal(
    query.sql.includes(";"),
    false
  );

  assert.throws(
    () =>
      createFdAdapter({
        schemaVerified: true,
        movementSemanticsVerified: false,
        movementDerivation: "direct_quantity",
        eventTypeLiteral: "dispensed",
        unitLiteral: "UNVERIFIED",
        fields: {
          eventId:
            profile.candidateAdapterMapping.eventId,
          itemId:
            profile.candidateAdapterMapping.itemId,
          quantity:
            profile.candidateAdapterMapping.quantityCandidate,
          occurredAt:
            profile.candidateAdapterMapping.occurredAtCandidate
        }
      }),
    /FD_MOVEMENT_SEMANTICS_VERIFICATION_REQUIRED/
  );

  assert.deepEqual(
    FD_OBSERVED_XFER_SOURCE_PROFILE,
    profile
  );

  console.log(
    "FD_XFER_RELATIONAL_SOURCE_PROFILE_TESTS_PASSED=TRUE"
  );
  console.log(
    "FD_XFER_JOIN_SHAPE_VERIFIED=TRUE"
  );
  console.log(
    "FD_XFER_SEMANTIC_PREDICATES_ENABLED=FALSE"
  );
  console.log(
    "FD_XFER_MOVEMENT_SEMANTICS_VERIFIED=FALSE"
  );
  console.log(
    "FD_XFER_ADAPTER_ACTIVATION_ALLOWED=FALSE"
  );
  console.log(
    "FD_XFER_PHI_SELECTED=FALSE"
  );
  console.log(
    "FD_STOCK_AUTHORITY=FALSE"
  );
  console.log(
    "FD_CLINIC_SCOPE_AUTHORITY=FALSE"
  );
})();
