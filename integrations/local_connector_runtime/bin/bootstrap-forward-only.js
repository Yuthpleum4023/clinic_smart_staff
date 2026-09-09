#!/usr/bin/env node
"use strict";

const path = require("path");

const {
  loadRuntimeConfig,
} = require("../src/config/loadConfig");

const {
  createRuntimeDependencies,
} = require("../src/runtime/runtimeFactory");

const {
  initializeForwardOnlyActivation,
} = require("../src/runtime/forwardOnlyActivation");

function s(value) {
  return String(value ?? "").trim();
}

async function main() {
  const configArg = s(process.argv[2]);
  if (!configArg) {
    throw new Error(
      "FORWARD_ONLY_CONFIG_PATH_REQUIRED"
    );
  }

  const configPath = path.resolve(configArg);
  const config = loadRuntimeConfig(configPath);

  const deps = createRuntimeDependencies(config);

  const result =
    await initializeForwardOnlyActivation({
      config,
      checkpointStore: deps.checkpointStore,
      env: process.env,
    });

  console.log(
    JSON.stringify(
      {
        ok: true,
        action: "forward_only_activation",
        initialized: result.initialized,
        alreadyInitialized:
          result.alreadyInitialized,
        checkpointReady: true,
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error(
    JSON.stringify(
      {
        ok: false,
        code: String(
          err?.code ||
          err?.message ||
          "FORWARD_ONLY_ACTIVATION_FAILED"
        ),
        message: String(
          err?.message ||
          "Forward-only activation failed"
        ),
      },
      null,
      2
    )
  );
  process.exitCode = 1;
});
