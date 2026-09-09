"use strict";

const {
  mysqlConnectionFactory
} = require(
  "../runtime/mysqlConnectionFactory"
);

function s(value) {
  return String(value ?? "").trim();
}

function positivePort(value) {
  const port = Number(value ?? 3306);

  if (
    !Number.isInteger(port) ||
    port <= 0 ||
    port > 65535
  ) {
    throw new Error(
      "SOURCE_CONNECTIVITY_PORT_INVALID"
    );
  }

  return port;
}

function requireSourceConfig(source) {
  if (
    !source ||
    typeof source !== "object" ||
    Array.isArray(source)
  ) {
    throw new Error(
      "SOURCE_CONNECTIVITY_CONFIG_REQUIRED"
    );
  }

  const host = s(source.host);
  const database = s(source.database);
  const user = s(source.user);
  const passwordEnv = s(source.passwordEnv);

  if (!host) {
    throw new Error(
      "SOURCE_CONNECTIVITY_HOST_REQUIRED"
    );
  }

  if (!database) {
    throw new Error(
      "SOURCE_CONNECTIVITY_DATABASE_REQUIRED"
    );
  }

  if (!user) {
    throw new Error(
      "SOURCE_CONNECTIVITY_USER_REQUIRED"
    );
  }

  if (!passwordEnv) {
    throw new Error(
      "SOURCE_CONNECTIVITY_PASSWORD_ENV_REQUIRED"
    );
  }

  return Object.freeze({
    host,
    port: positivePort(source.port),
    database,
    user,
    passwordEnv
  });
}

function resolveSourceSecret(
  source,
  env = process.env
) {
  const password =
    s(env[source.passwordEnv]);

  if (!password) {
    throw new Error(
      `SOURCE_DB_PASSWORD_ENV_MISSING:${source.passwordEnv}`
    );
  }

  return password;
}

async function checkMySqlSourceConnectivity(
  sourceInput,
  {
    env = process.env,
    connectionFactory =
      mysqlConnectionFactory
  } = {}
) {
  const source =
    requireSourceConfig(sourceInput);

  if (
    typeof connectionFactory !==
    "function"
  ) {
    throw new Error(
      "SOURCE_CONNECTIVITY_CONNECTION_FACTORY_REQUIRED"
    );
  }

  const password =
    resolveSourceSecret(
      source,
      env
    );

  let connection = null;

  try {
    connection =
      await connectionFactory({
        host: source.host,
        port: source.port,
        database: source.database,
        user: source.user,
        password,
        multipleStatements: false
      });

    if (
      !connection ||
      typeof connection.end !==
        "function"
    ) {
      throw new Error(
        "SOURCE_CONNECTIVITY_CONNECTION_CONTRACT_INVALID"
      );
    }

    /*
     * mysql2 createConnection already performs the
     * connection/authentication handshake.
     *
     * ping() is transport health only.
     * No business table is read here.
     */
    if (
      typeof connection.ping ===
      "function"
    ) {
      await connection.ping();
    }

    return Object.freeze({
      ok: true,
      driverId: "mysql",
      host: source.host,
      port: source.port,
      database: source.database,

      // Deliberately do not return username/password.
      credentialsExposed: false,

      businessRowsRead: false,
      semanticMappingPerformed: false,
      adapterActivated: false,
      stockAuthorityUsed: false,
      clinicScopeAuthorityUsed: false
    });
  } finally {
    if (
      connection &&
      typeof connection.end ===
        "function"
    ) {
      await connection.end();
    }
  }
}

module.exports = {
  requireSourceConfig,
  resolveSourceSecret,
  checkMySqlSourceConnectivity
};
