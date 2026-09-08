"use strict";

function isoNow(clock) {
  return new Date(clock()).toISOString();
}

function safeError(err) {
  return {
    code: String(err?.code || "CONNECTOR_RUN_FAILED"),
    message: String(err?.message || "Connector run failed")
  };
}

class ProductionRunner {
  constructor({
    runtime,
    healthStore,
    retryPolicy,
    pollIntervalMs = 30000,
    clock = Date.now,
    sleep = (ms) =>
      new Promise((resolve) => setTimeout(resolve, ms))
  }) {
    if (!runtime || typeof runtime.runOnce !== "function") {
      throw new Error("PRODUCTION_RUNTIME_REQUIRED");
    }

    if (!healthStore || typeof healthStore.write !== "function") {
      throw new Error("HEALTH_STORE_REQUIRED");
    }

    if (
      !retryPolicy ||
      typeof retryPolicy.delayForFailureCount !== "function"
    ) {
      throw new Error("RETRY_POLICY_REQUIRED");
    }

    this.runtime = runtime;
    this.healthStore = healthStore;
    this.retryPolicy = retryPolicy;
    this.pollIntervalMs = Math.max(1000, Number(pollIntervalMs) || 30000);
    this.clock = clock;
    this.sleep = sleep;

    this.stopping = false;
    this.running = false;
    this.failureCount = 0;
  }

  snapshot(extra = {}) {
    return {
      service: "clinic_smart_staff_connector",
      running: this.running,
      stopping: this.stopping,
      failureCount: this.failureCount,
      updatedAt: isoNow(this.clock),
      ...extra
    };
  }

  writeHealth(extra = {}) {
    this.healthStore.write(this.snapshot(extra));
  }

  requestStop() {
    this.stopping = true;
    this.writeHealth({
      status: "stopping"
    });
  }

  async runCycle() {
    const startedAt = isoNow(this.clock);

    try {
      const result = await this.runtime.runOnce();

      this.failureCount = 0;

      this.writeHealth({
        status: "healthy",
        lastCycleStartedAt: startedAt,
        lastSuccessAt: isoNow(this.clock),
        lastResult: result,
        lastError: null
      });

      return {
        ok: true,
        delayMs: this.pollIntervalMs,
        result
      };
    } catch (err) {
      this.failureCount += 1;

      const delayMs =
        this.retryPolicy.delayForFailureCount(
          this.failureCount
        );

      this.writeHealth({
        status: "degraded",
        lastCycleStartedAt: startedAt,
        lastFailureAt: isoNow(this.clock),
        nextRetryDelayMs: delayMs,
        lastError: safeError(err)
      });

      return {
        ok: false,
        delayMs,
        error: err
      };
    }
  }

  async start() {
    if (this.running) {
      throw new Error("PRODUCTION_RUNNER_ALREADY_RUNNING");
    }

    this.running = true;
    this.stopping = false;

    this.writeHealth({
      status: "starting",
      startedAt: isoNow(this.clock)
    });

    try {
      while (!this.stopping) {
        const outcome = await this.runCycle();

        if (this.stopping) break;

        await this.sleep(outcome.delayMs);
      }
    } finally {
      this.running = false;

      this.writeHealth({
        status: "stopped",
        stoppedAt: isoNow(this.clock)
      });
    }
  }
}

module.exports = { ProductionRunner };
