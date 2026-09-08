"use strict";

const {
  buildNormalizedConsumptionEvent
} = require("./normalizedEvent");

class ConnectorRuntime {
  constructor({ driver, adapter, transport, checkpointStore, checkpointKey }) {
    this.driver = driver;
    this.adapter = adapter;
    this.transport = transport;
    this.checkpointStore = checkpointStore;
    this.checkpointKey = String(checkpointKey || "").trim();

    if (!this.checkpointKey) throw new Error("CHECKPOINT_KEY_REQUIRED");
  }

  async runOnce() {
    await this.driver.connect();
    try {
      const checkpoint = this.checkpointStore.get(this.checkpointKey);
      const batch = await this.driver.poll({ checkpoint });
      const records = Array.isArray(batch?.records) ? batch.records : [];
      let sent = 0;

      for (const record of records) {
        const transformed = await this.adapter.transformRecord(record, { checkpoint });
        const events = Array.isArray(transformed) ? transformed : [transformed];

        for (const raw of events) {
          if (!raw) continue;
          const event = buildNormalizedConsumptionEvent(raw);
          await this.transport.sendConsumption(event);
          sent += 1;
        }
      }

      if (Object.prototype.hasOwnProperty.call(batch || {}, "nextCheckpoint")) {
        this.checkpointStore.set(this.checkpointKey, batch.nextCheckpoint);
      }

      return { ok: true, recordsRead: records.length, eventsSent: sent };
    } finally {
      await this.driver.close();
    }
  }
}

module.exports = { ConnectorRuntime };
