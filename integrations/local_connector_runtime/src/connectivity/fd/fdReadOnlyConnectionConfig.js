"use strict";
const FD_DATABASE = "FD5_5";
const FD_PORT = 3306;
const FD_PASSWORD_ENV = "CLINIC_SOURCE_DB_PASSWORD";
function s(value) { return String(value ?? "").trim(); }
function required(value, code) { const out = s(value); if (!out) throw new Error(code); return out; }
function buildFdReadOnlyConnectivityConfig(deployment = {}) {
  if (!deployment || typeof deployment !== "object" || Array.isArray(deployment)) throw new Error("FD_CONNECTIVITY_DEPLOYMENT_CONFIG_REQUIRED");
  const host = required(deployment.host, "FD_SOURCE_HOST_REQUIRED");
  const user = required(deployment.user, "FD_SOURCE_USER_REQUIRED");
  return Object.freeze({ driverId: "mysql", source: Object.freeze({ host, port: FD_PORT, database: FD_DATABASE, user, passwordEnv: FD_PASSWORD_ENV }) });
}
function assertFdReadOnlyConnectivityConfig(config) {
  if (!config || typeof config !== "object" || Array.isArray(config)) throw new Error("FD_CONNECTIVITY_CONFIG_REQUIRED");
  if (config.driverId !== "mysql") throw new Error("FD_CONNECTIVITY_DRIVER_MISMATCH");
  const source = config.source;
  if (!source || typeof source !== "object" || Array.isArray(source)) throw new Error("FD_CONNECTIVITY_SOURCE_REQUIRED");
  required(source.host, "FD_SOURCE_HOST_REQUIRED");
  required(source.user, "FD_SOURCE_USER_REQUIRED");
  if (source.port !== FD_PORT) throw new Error("FD_SOURCE_PORT_CONTRACT_MISMATCH");
  if (source.database !== FD_DATABASE) throw new Error("FD_DATABASE_CONTRACT_MISMATCH");
  if (source.passwordEnv !== FD_PASSWORD_ENV) throw new Error("FD_PASSWORD_ENV_CONTRACT_MISMATCH");
  if (Object.prototype.hasOwnProperty.call(source, "password")) throw new Error("FD_PASSWORD_MUST_NOT_BE_EMBEDDED");
  return true;
}
module.exports = { FD_DATABASE, FD_PORT, FD_PASSWORD_ENV, buildFdReadOnlyConnectivityConfig, assertFdReadOnlyConnectivityConfig };
