"use strict";
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { loadRuntimeConfig } = require("../src/config/loadConfig");
const { createRuntimeDependencies } = require("../src/runtime/runtimeFactory");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "css-ready-"));
const configPath = path.join(tmp, "connector-config.json");
fs.writeFileSync(configPath, JSON.stringify({
  baseUrl: "https://inventory.example",
  connectorTokenEnv: "CLINIC_CONNECTOR_TOKEN",
  driverId: "mysql",
  adapterId: "fd",
  checkpointKey: "verified-source",
  checkpointFile: path.join(tmp, "checkpoint.json"),
  healthFile: path.join(tmp, "health.json"),
  pollIntervalMs: 45000,
  retry: { initialDelayMs: 2000, maxDelayMs: 10000, multiplier: 2 },
  source: {
    host: "127.0.0.1", port: 3306, database: "verified_db",
    user: "readonly_user", passwordEnv: "CLINIC_SOURCE_DB_PASSWORD",
    poll: {
      schema: "verified_db", table: "verified_usage",
      columns: ["event_key","line_key","item_key","prv_amount_unit","amount_unit","occurred_at"],
      cursorColumn: "occurred_at", tieBreakerColumn: "line_key", limit: 50
    }
  },
  adapterProfile: {
    schemaVerified: true, movementSemanticsVerified: true,
    sourceName: "fd", unitLiteral: "fd_amount_unit",
    fields: {
      eventId: "event_key", lineId: "line_key", itemId: "item_key",
      previousAmountUnit: "prv_amount_unit", amountUnit: "amount_unit",
      unit: "", occurredAt: "occurred_at",
      referenceNo: "", referenceType: ""
    }
  }
}, null, 2));

const env = {
  CLINIC_CONNECTOR_TOKEN: "fixture-token",
  CLINIC_SOURCE_DB_PASSWORD: "fixture-password"
};
const config = loadRuntimeConfig(configPath, env);
assert.equal(config.healthFile, path.join(tmp, "health.json"));
assert.equal(config.pollIntervalMs, 45000);
assert.equal(config.retry.initialDelayMs, 2000);
assert.equal(config.adapterProfile.schemaVerified, true);

let mysqlConfig = null;
const deps = createRuntimeDependencies(config, {
  env,
  mysqlConnectionFactory: async cfg => {
    mysqlConfig = cfg;
    return { execute: async () => [[], []], end: async () => {} };
  },
  transport: { sendConsumption: async () => ({ ok: true }) }
});
assert.ok(deps.driver);
assert.ok(deps.adapter);
assert.equal(mysqlConfig, null);

const root = path.resolve(__dirname, "..");
const pkg = JSON.parse(fs.readFileSync(path.join(root,"package.json"),"utf8"));
const lock = JSON.parse(fs.readFileSync(path.join(root,"package-lock.json"),"utf8"));
assert.ok(pkg.dependencies?.mysql2);
assert.ok(lock.packages?.["node_modules/mysql2"]);

const layout = fs.readFileSync(path.join(root,"packaging/windows/build_pipeline/build-layout.ps1"),"utf8");
const verify = fs.readFileSync(path.join(root,"packaging/windows/build_pipeline/verify-build-layout.ps1"),"utf8");
assert.match(layout, /npm\.cmd/);
assert.match(layout, /ci --omit=dev --ignore-scripts/);
assert.match(verify, /node_modules\\mysql2\\package\.json/);

console.log("PRODUCTION_ARTIFACT_READINESS_TESTS_PASSED=TRUE");
console.log("CONFIG_TO_RUNTIME_CONTRACT=PASS");
console.log("PACKAGE_LOCK_CONTRACT=PASS");
console.log("CLEAN_WINDOWS_DEPENDENCY_LAYOUT_CONTRACT=PASS");
