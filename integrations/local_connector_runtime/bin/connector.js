#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  loadRuntimeConfig
} = require("../src/config/loadConfig");

const {
  ConnectorRuntime
} = require("../src/core/connectorRuntime");

const {
  FileHealthStore
} = require("../src/core/healthStore");

const {
  createRetryPolicy
} = require("../src/core/retryPolicy");

const {
  ProductionRunner
} = require("../src/runtime/productionRunner");

const {
  createRuntimeDependencies
} = require("../src/runtime/runtimeFactory");

function s(value) {
  return String(value ?? "").trim();
}

async function main() {
  const configPath =
    path.resolve(
      s(process.env.CONNECTOR_CONFIG_PATH) ||
      process.argv[2] ||
      "./connector-config.json"
    );

  const config =
    loadRuntimeConfig(configPath);

  const deps =
    createRuntimeDependencies(config);

  const runtime =
    new ConnectorRuntime(deps);

  const healthFile =
    path.resolve(
      s(config.healthFile) ||
      "./state/health.json"
    );

  const runner =
    new ProductionRunner({
      runtime,
      healthStore:
        new FileHealthStore(
          healthFile
        ),
      retryPolicy:
        createRetryPolicy(
          config.retry || {}
        ),
      pollIntervalMs:
        Number(
          config.pollIntervalMs
        ) || 30000
    });

  let stopping = false;

  function stop() {
    if (stopping) return;
    stopping = true;
    runner.requestStop();
  }

  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);

  process.on(
    "uncaughtException",
    (err) => {
      console.error(err);
      runner.requestStop();
      process.exitCode = 1;
    }
  );

  process.on(
    "unhandledRejection",
    (err) => {
      console.error(err);
      runner.requestStop();
      process.exitCode = 1;
    }
  );

  await runner.start();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
