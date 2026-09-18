"use strict";

const assert = require("assert");

const {
  resolveIntegrationMovement
} = require(
  "../services/integrationProcessingService"
);

const reversal =
  resolveIntegrationMovement(
    "reversal",
    2
  );

assert.deepEqual(reversal, {
  type: "reversal",
  quantityDelta: 2,
  reason:
    "external dispensing reversal"
});

const dispensed =
  resolveIntegrationMovement(
    "dispensed",
    2
  );

assert.equal(
  dispensed.type,
  "external_consumption"
);
assert.equal(
  dispensed.quantityDelta,
  -2
);

console.log(
  "INTEGRATION_REVERSAL_CONTRACT_TESTS_PASSED=TRUE"
);
console.log(
  "REVERSAL_MATERIALIZED_AS_STOCK_IN=FALSE"
);
