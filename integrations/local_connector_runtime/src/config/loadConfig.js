"use strict";

const fs = require("fs");
const path = require("path");

function s(v) {
  return String(v ?? "").trim();
}

function loadRuntimeConfig(filePath, env = process.env) {
  const config = JSON.parse(fs.readFileSync(path.resolve(filePath), "utf8"));

  if ("clinicId" in config) {
    throw new Error("CLINIC_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY");
  }

  const tokenEnv = s(config.connectorTokenEnv);
  if (!tokenEnv) throw new Error("CONNECTOR_TOKEN_ENV_REQUIRED");

  const connectorToken = s(env[tokenEnv]);
  if (!connectorToken) throw new Error(`CONNECTOR_TOKEN_ENV_MISSING:${tokenEnv}`);

  return {
    baseUrl: s(config.baseUrl),
    connectorToken,
    driverId: s(config.driverId),
    adapterId: s(config.adapterId),
    checkpointKey: s(config.checkpointKey),
    checkpointFile: s(config.checkpointFile),
    healthFile: s(config.healthFile),
    pollIntervalMs: config.pollIntervalMs,
    retry: config.retry || {},
    source: config.source || {},
    adapterProfile: config.adapterProfile || {}
  };
}

module.exports = { loadRuntimeConfig };
