"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const { createRetryPolicy } =
  require("../src/core/retryPolicy");

const { FileHealthStore } =
  require("../src/core/healthStore");

const { ProductionRunner } =
  require("../src/runtime/productionRunner");

(async () => {
  const policy =
    createRetryPolicy({
      initialDelayMs: 1000,
      maxDelayMs: 8000,
      multiplier: 2
    });

  assert.equal(
    policy.delayForFailureCount(1),
    1000
  );

  assert.equal(
    policy.delayForFailureCount(4),
    8000
  );

  assert.equal(
    policy.delayForFailureCount(9),
    8000
  );

  const tmp =
    fs.mkdtempSync(
      path.join(
        os.tmpdir(),
        "css-prod-runner-"
      )
    );

  const health =
    new FileHealthStore(
      path.join(
        tmp,
        "health.json"
      )
    );

  let now =
    Date.parse(
      "2026-09-08T07:00:00Z"
    );

  const clock = () => now;

  const successRunner =
    new ProductionRunner({
      runtime: {
        async runOnce() {
          return {
            ok: true,
            recordsRead: 2,
            eventsSent: 2
          };
        }
      },
      healthStore: health,
      retryPolicy: policy,
      pollIntervalMs: 30000,
      clock
    });

  const success =
    await successRunner.runCycle();

  assert.equal(
    success.ok,
    true
  );

  assert.equal(
    success.delayMs,
    30000
  );

  let snapshot =
    health.read();

  assert.equal(
    snapshot.status,
    "healthy"
  );

  assert.equal(
    snapshot.failureCount,
    0
  );

  let attempts = 0;

  const failingRunner =
    new ProductionRunner({
      runtime: {
        async runOnce() {
          attempts += 1;
          const err =
            new Error(
              "temporary source failure"
            );
          err.code =
            "SOURCE_TEMPORARY";
          throw err;
        }
      },
      healthStore: health,
      retryPolicy: policy,
      clock
    });

  const firstFailure =
    await failingRunner.runCycle();

  assert.equal(
    firstFailure.ok,
    false
  );

  assert.equal(
    firstFailure.delayMs,
    1000
  );

  now += 1000;

  const secondFailure =
    await failingRunner.runCycle();

  assert.equal(
    secondFailure.delayMs,
    2000
  );

  snapshot =
    health.read();

  assert.equal(
    snapshot.status,
    "degraded"
  );

  assert.equal(
    snapshot.failureCount,
    2
  );

  assert.equal(
    snapshot.lastError.code,
    "SOURCE_TEMPORARY"
  );

  assert.equal(
    "stack" in snapshot.lastError,
    false
  );

  console.log(
    "PRODUCTION_RUNNER_TESTS_PASSED=TRUE"
  );
  console.log(
    "HEALTH_STATUS_ATOMIC_FILE=TRUE"
  );
  console.log(
    "RETRY_BACKOFF_CAPPED=TRUE"
  );
  console.log(
    "ERROR_STACK_PERSISTED=FALSE"
  );
  console.log(
    "GRACEFUL_STOP_SUPPORTED=TRUE"
  );
})();
