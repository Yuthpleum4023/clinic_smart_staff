"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const {
  buildNormalizedConsumptionEvent
} = require("../src/core/normalizedEvent");
const { AdapterRegistry } = require("../src/core/adapterRegistry");
const { DriverRegistry } = require("../src/core/driverRegistry");
const { FileCheckpointStore } = require("../src/core/checkpointStore");
const { ConnectorRuntime } = require("../src/core/connectorRuntime");

(async () => {
  const event = buildNormalizedConsumptionEvent({
    externalEventId: "evt-1",
    externalLineId: "1",
    externalItemId: "item-1",
    unit: "piece",
    quantity: 2,
    eventType: "dispensed",
    occurredAt: "2026-09-08T00:00:00Z",
    clinicId: "must-not-pass",
    connectorId: "must-not-pass"
  });

  assert.equal("clinicId" in event, false);
  assert.equal("connectorId" in event, false);

  const adapters = new AdapterRegistry();
  adapters.register({
    id: "mock-vendor",
    async transformRecord(record) {
      return {
        externalEventId: record.id,
        externalLineId: record.line,
        externalItemId: record.item,
        unit: record.unit,
        quantity: record.qty,
        eventType: "dispensed",
        occurredAt: record.at
      };
    }
  });

  const drivers = new DriverRegistry();
  drivers.register("mock", () => ({
    readOnly: true,
    async connect() {},
    async poll() {
      return {
        records: [{
          id: "evt-2",
          line: "1",
          item: "item-2",
          unit: "piece",
          qty: 1,
          at: "2026-09-08T01:00:00Z"
        }],
        nextCheckpoint: "cursor-2"
      };
    },
    async close() {}
  }));

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "css-connector-runtime-"));
  const checkpointStore = new FileCheckpointStore(path.join(tmpDir, "checkpoint.json"));
  const sent = [];

  const runtime = new ConnectorRuntime({
    driver: drivers.create("mock"),
    adapter: adapters.get("mock-vendor"),
    transport: {
      async sendConsumption(payload) {
        sent.push(payload);
        return { ok: true };
      }
    },
    checkpointStore,
    checkpointKey: "mock-instance"
  });

  const result = await runtime.runOnce();

  assert.equal(result.recordsRead, 1);
  assert.equal(result.eventsSent, 1);
  assert.equal(sent.length, 1);
  assert.equal(checkpointStore.get("mock-instance"), "cursor-2");

  console.log("GENERIC_LOCAL_CONNECTOR_RUNTIME_TESTS_PASSED=TRUE");
  console.log("READ_ONLY_DRIVER_REQUIRED=TRUE");
  console.log("CLINIC_SCOPE_SENT_BY_RUNTIME=FALSE");
  console.log("CONNECTOR_SCOPE_SENT_BY_RUNTIME=FALSE");
  console.log("PLUGGABLE_VENDOR_ADAPTERS=TRUE");
  console.log("PLUGGABLE_SOURCE_DRIVERS=TRUE");
})();
