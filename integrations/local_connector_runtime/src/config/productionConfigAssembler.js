"use strict";

const {
  DEFAULT_VERIFIED_PROFILE_REGISTRY,
} = require("../adapters/verifiedProfileRegistry");

function s(value) {
  return String(value ?? "").trim();
}

function required(value, code) {
  const normalized = s(value);
  if (!normalized) throw new Error(code);
  return normalized;
}

function positiveInteger(value, fallback, code) {
  const number = Number(value ?? fallback);
  if (!Number.isInteger(number) || number <= 0) throw new Error(code);
  return number;
}

function assertNoSemanticOverrides(document) {
  if (Object.prototype.hasOwnProperty.call(document, "adapterProfile")) {
    throw new Error("ADAPTER_PROFILE_MUST_COME_FROM_VERIFIED_REGISTRY");
  }

  const source = document.source || {};
  for (const field of ["database", "poll"]) {
    if (Object.prototype.hasOwnProperty.call(source, field)) {
      throw new Error(`SOURCE_${field.toUpperCase()}_MUST_COME_FROM_VERIFIED_REGISTRY`);
    }
  }
}

function assembleProductionConfig(
  document = {},
  {
    env = process.env,
    profileRegistry = DEFAULT_VERIFIED_PROFILE_REGISTRY,
  } = {}
) {
  if (!document || typeof document !== "object" || Array.isArray(document)) {
    throw new Error("PRODUCTION_CONFIG_REQUIRED");
  }
  if ("clinicId" in document) {
    throw new Error("CLINIC_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY");
  }
  if ("connectorId" in document) {
    throw new Error("CONNECTOR_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY");
  }

  assertNoSemanticOverrides(document);

  const adapterId = required(document.adapterId, "ADAPTER_ID_REQUIRED");
  const profileId = required(document.profileId, "VERIFIED_PROFILE_ID_REQUIRED");
  const profile = profileRegistry.get(adapterId, profileId);
  const requestedDriverId = required(document.driverId, "DRIVER_ID_REQUIRED");

  if (requestedDriverId !== profile.driverId) {
    throw new Error("DRIVER_MUST_MATCH_VERIFIED_PROFILE");
  }

  const tokenEnv = required(
    document.connectorTokenEnv,
    "CONNECTOR_TOKEN_ENV_REQUIRED"
  );
  const connectorToken = required(
    env[tokenEnv],
    `CONNECTOR_TOKEN_ENV_MISSING:${tokenEnv}`
  );
  const source = document.source;

  if (!source || typeof source !== "object" || Array.isArray(source)) {
    throw new Error("SOURCE_CONFIG_REQUIRED");
  }

  return Object.freeze({
    baseUrl: required(document.baseUrl, "BASE_URL_REQUIRED"),
    connectorToken,
    driverId: profile.driverId,
    adapterId: profile.adapterId,
    profileId: profile.profileId,
    checkpointKey: required(document.checkpointKey, "CHECKPOINT_KEY_REQUIRED"),
    checkpointFile: required(document.checkpointFile, "CHECKPOINT_FILE_REQUIRED"),
    healthFile: required(document.healthFile, "HEALTH_FILE_REQUIRED"),
    pollIntervalMs: positiveInteger(
      document.pollIntervalMs,
      30000,
      "POLL_INTERVAL_INVALID"
    ),
    retry: document.retry || {},
    source: Object.freeze({
      host: required(source.host, "SOURCE_HOST_REQUIRED"),
      port: positiveInteger(source.port, 3306, "SOURCE_PORT_INVALID"),
      database: profile.source.database,
      user: required(source.user, "SOURCE_USER_REQUIRED"),
      passwordEnv: required(
        source.passwordEnv,
        "SOURCE_DB_PASSWORD_ENV_REQUIRED"
      ),
      poll: profile.source.poll,
    }),
    adapterProfile: profile.adapterProfile,
  });
}

module.exports = {
  assertNoSemanticOverrides,
  assembleProductionConfig,
};
