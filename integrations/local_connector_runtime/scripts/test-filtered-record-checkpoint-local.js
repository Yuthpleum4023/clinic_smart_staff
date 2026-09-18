"use strict";

const assert = require("assert");

const {
  ConnectorRuntime
} = require("../src/core/connectorRuntime");

function checkpointStore(initial = null) {
  const values = new Map();

  if (initial !== null) {
    values.set("fd-instance", initial);
  }

  return {
    get(key) {
      return values.get(key);
    },
    set(key, value) {
      values.set(key, value);
    }
  };
}

(async () => {
  /*
   * A successfully observed but semantically excluded source row
   * must advance the forward-only checkpoint without sending it.
   */
  const ignoredStore =
    checkpointStore({ cursor: 100 });

  let ignoredTransportCalls = 0;

  const ignoredRuntime =
    new ConnectorRuntime({
      driver: {
        async connect() {},
        async poll() {
          return {
            records: [{
              id: 101,
              documentType:
                "unverified-movement"
            }],
            nextCheckpoint: {
              cursor: 101
            }
          };
        },
        async close() {}
      },
      adapter: {
        async transformRecord() {
          return null;
        }
      },
      transport: {
        async sendMovement() {
          ignoredTransportCalls += 1;
        }
      },
      checkpointStore:
        ignoredStore,
      checkpointKey:
        "fd-instance"
    });

  const ignoredResult =
    await ignoredRuntime.runOnce();

  assert.deepEqual(
    ignoredResult,
    {
      ok: true,
      recordsRead: 1,
      eventsSent: 0
    }
  );

  assert.equal(
    ignoredTransportCalls,
    0
  );

  assert.deepEqual(
    ignoredStore.get("fd-instance"),
    { cursor: 101 }
  );

  /*
   * A failed transformation must not advance checkpoint.
   */
  const failedStore =
    checkpointStore({ cursor: 200 });

  const failedRuntime =
    new ConnectorRuntime({
      driver: {
        async connect() {},
        async poll() {
          return {
            records: [{
              id: 201
            }],
            nextCheckpoint: {
              cursor: 201
            }
          };
        },
        async close() {}
      },
      adapter: {
        async transformRecord() {
          throw new Error(
            "TRANSFORM_FAILED"
          );
        }
      },
      transport: {
        async sendMovement() {
          throw new Error(
            "TRANSPORT_MUST_NOT_RUN"
          );
        }
      },
      checkpointStore:
        failedStore,
      checkpointKey:
        "fd-instance"
    });

  await assert.rejects(
    () => failedRuntime.runOnce(),
    /TRANSFORM_FAILED/
  );

  assert.deepEqual(
    failedStore.get("fd-instance"),
    { cursor: 200 }
  );

  console.log(
    "FILTERED_RECORD_CHECKPOINT_ADVANCED=TRUE"
  );
  console.log(
    "FILTERED_RECORD_EVENT_SENT=FALSE"
  );
  console.log(
    "FAILED_BATCH_CHECKPOINT_ADVANCED=FALSE"
  );
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
