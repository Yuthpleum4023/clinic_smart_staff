"use strict";

const path = require("path");

const { FileCheckpointStore } =
  require("../core/checkpointStore");

const { InventoryIngestionClient } =
  require("../core/transportClient");

const { createMySqlReadOnlyDriver } =
  require("../drivers/mysqlReadOnlyDriver");

const { createFdAdapter } =
  require("../adapters/fdAdapter");

const { mysqlConnectionFactory } =
  require("./mysqlConnectionFactory");

function s(value) {
  return String(value ?? "").trim();
}

function requireObject(value, code) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(code);
  }
  return value;
}

function createDriver(config, deps = {}) {
  const driverId = s(config.driverId);

  if (driverId === "mysql") {
    const source = {
      ...requireObject(
        config.source,
        "SOURCE_CONFIG_REQUIRED"
      )
    };

    const passwordEnv =
      s(source.passwordEnv);

    if (passwordEnv) {
      const password =
        s(
          (deps.env || process.env)[
            passwordEnv
          ]
        );

      if (!password) {
        throw new Error(
          `SOURCE_DB_PASSWORD_ENV_MISSING:${passwordEnv}`
        );
      }

      source.password = password;
    }

    delete source.passwordEnv;

    return createMySqlReadOnlyDriver(
      source,
      {
        connectionFactory:
          deps.mysqlConnectionFactory ||
          mysqlConnectionFactory
      }
    );
  }

  throw new Error(`UNSUPPORTED_DRIVER:${driverId}`);
}

function createAdapter(config) {
  const adapterId = s(config.adapterId);

  if (adapterId === "fd") {
    return createFdAdapter(
      requireObject(
        config.adapterProfile,
        "ADAPTER_PROFILE_REQUIRED"
      )
    );
  }

  throw new Error(`UNSUPPORTED_ADAPTER:${adapterId}`);
}

function createRuntimeDependencies(config, deps = {}) {
  const checkpointFile = path.resolve(config.checkpointFile);

  return {
    driver: createDriver(config, deps),
    adapter: createAdapter(config),

    transport:
      deps.transport ||
      new InventoryIngestionClient({
        baseUrl: config.baseUrl,
        connectorToken: config.connectorToken,
        fetchImpl: deps.fetchImpl || globalThis.fetch
      }),

    checkpointStore:
      deps.checkpointStore ||
      new FileCheckpointStore(checkpointFile),

    checkpointKey: config.checkpointKey
  };
}

module.exports = {
  createDriver,
  createAdapter,
  createRuntimeDependencies
};
