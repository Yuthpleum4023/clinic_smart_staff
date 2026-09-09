"use strict";

const assert = require("assert");

const {
  FD_VERIFIED_SCHEMA,
  assertFdSchemaContract
} = require(
  "../src/adapters/fd/verifiedSchemaContract"
);

assert.equal(
  assertFdSchemaContract(),
  true
);

assert.equal(
  FD_VERIFIED_SCHEMA.source.database,
  "FD5_5"
);

assert.equal(
  FD_VERIFIED_SCHEMA.production.schemaCoordinatesVerified,
  true
);

assert.equal(
  FD_VERIFIED_SCHEMA.production.movementSemanticsVerified,
  false
);

assert.equal(
  FD_VERIFIED_SCHEMA.production.adapterActivationAllowed,
  false
);

assert.equal(
  FD_VERIFIED_SCHEMA.production.stockAuthority,
  false
);

assert.equal(
  FD_VERIFIED_SCHEMA.production.clinicScopeAuthority,
  false
);

assert.equal(
  FD_VERIFIED_SCHEMA.production.fuzzyMappingAllowed,
  false
);

assert(
  FD_VERIFIED_SCHEMA.tables.product.columns.includes(
    "ProdNum"
  )
);

assert(
  FD_VERIFIED_SCHEMA.tables.xferdtl.columns.includes(
    "AmountUnit"
  )
);

assert(
  FD_VERIFIED_SCHEMA.tables.xferhdr.columns.includes(
    "DocType"
  )
);

assert(
  FD_VERIFIED_SCHEMA.tables.procprod.columns.includes(
    "AmtUnit"
  )
);

assert(
  FD_VERIFIED_SCHEMA.unresolvedSemantics.length > 0
);

console.log("FD_VERIFIED_SCHEMA_CONTRACT_TESTS_PASSED=TRUE");
console.log("FD_SCHEMA_COORDINATES_VERIFIED=TRUE");
console.log("FD_MOVEMENT_SEMANTICS_VERIFIED=FALSE");
console.log("FD_ADAPTER_ACTIVATION_ALLOWED=FALSE");
console.log("FD_STOCK_AUTHORITY=FALSE");
console.log("FD_CLINIC_SCOPE_AUTHORITY=FALSE");
console.log("FD_FUZZY_MAPPING_ALLOWED=FALSE");
