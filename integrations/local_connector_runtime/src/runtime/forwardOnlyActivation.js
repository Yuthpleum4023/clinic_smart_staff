"use strict";

const {
  normalizePollSpec,
  normalizeCheckpoint,
} = require("../drivers/mysqlReadOnlyDriver");

const {
  mysqlConnectionFactory,
} = require("./mysqlConnectionFactory");

function s(value) {
  return String(value ?? "").trim();
}

function codedError(code, message = code) {
  const err = new Error(message);
  err.code = code;
  return err;
}

function normalizedPort(value) {
  const port = Number(value ?? 3306);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw codedError(
      "SOURCE_PORT_INVALID",
      "Source database port must be a valid TCP port"
    );
  }
  return port;
}

function cloneCheckpoint(checkpoint) {
  return JSON.parse(JSON.stringify(checkpoint));
}

function checkpointEqual(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function validateCheckpointForConfig(config, checkpoint) {
  const driverId = s(config?.driverId);

  if (driverId !== "mysql") {
    throw codedError(
      "FORWARD_ONLY_DRIVER_UNSUPPORTED",
      `Forward-only activation is not implemented for driver: ${driverId || "unknown"}`
    );
  }

  const hasTieBreaker = Boolean(
    s(config?.source?.poll?.tieBreakerColumn)
  );

  return normalizeCheckpoint(
    checkpoint,
    hasTieBreaker
  );
}

async function captureMySqlTailCheckpoint(
  source = {},
  deps = {}
) {
  const poll = source.poll || {};
  const spec = normalizePollSpec(poll);
  const env = deps.env || process.env;

  const passwordEnv = s(source.passwordEnv);
  if (!passwordEnv) {
    throw codedError(
      "SOURCE_DB_PASSWORD_ENV_REQUIRED",
      "Source database password environment variable name is required"
    );
  }

  const password = s(env[passwordEnv]);
  if (!password) {
    throw codedError(
      "SOURCE_DB_PASSWORD_ENV_MISSING",
      `Source database password environment variable is missing: ${passwordEnv}`
    );
  }

  const connectionFactory =
    deps.connectionFactory ||
    mysqlConnectionFactory;

  const connection = await connectionFactory({
    host: s(source.host),
    port: normalizedPort(source.port),
    database: s(source.database),
    user: s(source.user),
    password,
    multipleStatements: false,
  });

  if (
    !connection ||
    typeof connection.execute !== "function" ||
    typeof connection.end !== "function"
  ) {
    throw codedError(
      "MYSQL_CONNECTION_CONTRACT_INVALID",
      "MySQL connection contract is invalid"
    );
  }

  try {
    const selectSql = spec.tieBreakerColumn
      ? `${spec.cursorColumn}, ${spec.tieBreakerColumn}`
      : spec.cursorColumn;

    const orderSql = spec.tieBreakerColumn
      ? `ORDER BY ${spec.cursorColumn} DESC, ${spec.tieBreakerColumn} DESC`
      : `ORDER BY ${spec.cursorColumn} DESC`;

    const sql = [
      `SELECT ${selectSql}`,
      `FROM ${spec.table}`,
      orderSql,
      "LIMIT 1",
    ].join(" ");

    const [rows] = await connection.execute(sql, []);

    if (!Array.isArray(rows)) {
      throw codedError(
        "MYSQL_ROWS_INVALID",
        "MySQL tail query did not return an array"
      );
    }

    if (rows.length === 0) {
      return null;
    }

    const row = rows[0];
    const cursorField = s(poll.cursorColumn);
    const cursor = row?.[cursorField];

    if (cursor === undefined || cursor === null) {
      throw codedError(
        "MYSQL_CURSOR_VALUE_MISSING",
        "Source tail row is missing the cursor value"
      );
    }

    const checkpoint = { cursor };

    const tieBreakerField = s(poll.tieBreakerColumn);
    if (tieBreakerField) {
      const tieBreaker = row?.[tieBreakerField];
      if (tieBreaker === undefined || tieBreaker === null) {
        throw codedError(
          "MYSQL_TIE_BREAKER_VALUE_MISSING",
          "Source tail row is missing the tie-breaker value"
        );
      }
      checkpoint.tieBreaker = tieBreaker;
    }

    return checkpoint;
  } finally {
    await connection.end();
  }
}

async function captureTailCheckpoint(
  config,
  deps = {}
) {
  const driverId = s(config?.driverId);

  if (driverId === "mysql") {
    return captureMySqlTailCheckpoint(
      config.source || {},
      deps
    );
  }

  throw codedError(
    "FORWARD_ONLY_DRIVER_UNSUPPORTED",
    `Forward-only activation is not implemented for driver: ${driverId || "unknown"}`
  );
}

function assertForwardOnlyActivation({
  config,
  checkpointStore,
}) {
  if (
    !checkpointStore ||
    typeof checkpointStore.get !== "function"
  ) {
    throw codedError(
      "CHECKPOINT_STORE_REQUIRED",
      "Checkpoint store is required for forward-only activation"
    );
  }

  const checkpointKey = s(config?.checkpointKey);
  if (!checkpointKey) {
    throw codedError(
      "CHECKPOINT_KEY_REQUIRED",
      "Checkpoint key is required for forward-only activation"
    );
  }

  const checkpoint = checkpointStore.get(checkpointKey);

  if (checkpoint === null) {
    throw codedError(
      "FORWARD_ONLY_ACTIVATION_REQUIRED",
      "Forward-only checkpoint must be initialized before connector start"
    );
  }

  return validateCheckpointForConfig(
    config,
    checkpoint
  );
}

async function initializeForwardOnlyActivation({
  config,
  checkpointStore,
  env = process.env,
  captureTailCheckpointImpl = captureTailCheckpoint,
}) {
  if (
    !checkpointStore ||
    typeof checkpointStore.get !== "function" ||
    typeof checkpointStore.set !== "function"
  ) {
    throw codedError(
      "CHECKPOINT_STORE_REQUIRED",
      "Readable and writable checkpoint store is required"
    );
  }

  const checkpointKey = s(config?.checkpointKey);
  if (!checkpointKey) {
    throw codedError(
      "CHECKPOINT_KEY_REQUIRED",
      "Checkpoint key is required"
    );
  }

  const existing = checkpointStore.get(checkpointKey);

  if (existing !== null) {
    const normalized = validateCheckpointForConfig(
      config,
      existing
    );

    return {
      ok: true,
      initialized: false,
      alreadyInitialized: true,
      checkpoint: cloneCheckpoint(normalized),
    };
  }

  const captured = await captureTailCheckpointImpl(
    config,
    { env }
  );

  if (captured === null) {
    throw codedError(
      "FORWARD_ONLY_SOURCE_TAIL_EMPTY",
      "Source has no tail row; refusing to start without a durable cutover checkpoint"
    );
  }

  const normalized = validateCheckpointForConfig(
    config,
    captured
  );

  const expected = cloneCheckpoint(normalized);

  checkpointStore.set(
    checkpointKey,
    expected
  );

  const persisted = checkpointStore.get(checkpointKey);
  if (persisted === null) {
    throw codedError(
      "FORWARD_ONLY_CHECKPOINT_PERSIST_FAILED",
      "Forward-only checkpoint was not persisted"
    );
  }

  const persistedNormalized = cloneCheckpoint(
    validateCheckpointForConfig(
      config,
      persisted
    )
  );

  if (!checkpointEqual(expected, persistedNormalized)) {
    throw codedError(
      "FORWARD_ONLY_CHECKPOINT_VERIFY_FAILED",
      "Persisted forward-only checkpoint does not match captured source tail"
    );
  }

  return {
    ok: true,
    initialized: true,
    alreadyInitialized: false,
    checkpoint: persistedNormalized,
  };
}

module.exports = {
  validateCheckpointForConfig,
  captureMySqlTailCheckpoint,
  captureTailCheckpoint,
  assertForwardOnlyActivation,
  initializeForwardOnlyActivation,
};
