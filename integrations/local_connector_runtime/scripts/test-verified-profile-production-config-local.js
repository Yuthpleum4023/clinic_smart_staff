"use strict";

const assert = require("assert");

const {
  FD_OBSERVED_XFER_SOURCE_PROFILE,
} = require("../src/adapters/fd/observedXferSourceProfile");

const {
  DEFAULT_VERIFIED_PROFILE_REGISTRY,
} = require("../src/adapters/verifiedProfileRegistry");

const {
  assembleProductionConfig,
} = require("../src/config/productionConfigAssembler");

const deploymentConfig = {
  baseUrl: "https://inventory.example",
  connectorTokenEnv: "CLINIC_CONNECTOR_TOKEN",
  driverId: "mysql",
  adapterId: "fd",
  profileId: "fd_xfer_relational_candidate_v1",
  checkpointKey: "backend-issued-source-instance",
  checkpointFile: "./state/checkpoints.json",
  healthFile: "./state/health.json",
  pollIntervalMs: 30000,
  retry: {
    initialDelayMs: 5000,
    maxDelayMs: 300000,
    multiplier: 2,
  },
  source: {
    host: "192.168.211.181",
    port: 3306,
    user: "clinicfd_ro",
    passwordEnv: "CLINIC_SOURCE_DB_PASSWORD",
  },
};

const env = {
  CLINIC_CONNECTOR_TOKEN: "fixture-token",
};

const config = assembleProductionConfig(deploymentConfig, { env });
const verified = FD_OBSERVED_XFER_SOURCE_PROFILE;

assert.equal(config.profileId, verified.id);
assert.equal(config.driverId, verified.source.engine);
assert.equal(config.source.database, verified.source.database);
assert.deepEqual(config.source.poll, verified.source.poll);
assert.deepEqual(config.adapterProfile, verified.adapterProfile);
assert.equal(config.source.host, "192.168.211.181");
assert.equal(config.source.user, "clinicfd_ro");

assert.deepEqual(
  DEFAULT_VERIFIED_PROFILE_REGISTRY.list(),
  ["fd:fd_xfer_relational_candidate_v1"]
);

for (const mutation of [
  { adapterProfile: verified.adapterProfile },
  { source: { ...deploymentConfig.source, database: "other" } },
  { source: { ...deploymentConfig.source, poll: verified.source.poll } },
]) {
  assert.throws(
    () => assembleProductionConfig({ ...deploymentConfig, ...mutation }, { env }),
    /MUST_COME_FROM_VERIFIED_REGISTRY/
  );
}

assert.throws(
  () => assembleProductionConfig({ ...deploymentConfig, profileId: "unknown" }, { env }),
  /VERIFIED_PROFILE_NOT_FOUND/
);

assert.throws(
  () => assembleProductionConfig({ ...deploymentConfig, driverId: "postgres" }, { env }),
  /DRIVER_MUST_MATCH_VERIFIED_PROFILE/
);

assert.throws(
  () => assembleProductionConfig({ ...deploymentConfig, clinicId: "forbidden" }, { env }),
  /CLINIC_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY/
);

console.log("VERIFIED_PROFILE_PRODUCTION_CONFIG_TESTS_PASSED=TRUE");
console.log("DEPLOYMENT_CAN_OVERRIDE_SEMANTICS=FALSE");
console.log("FD_PROFILE_RESOLVED_FROM_REGISTRY=TRUE");
console.log("VENDOR_PROFILE_REGISTRY_EXTENSIBLE=TRUE");
