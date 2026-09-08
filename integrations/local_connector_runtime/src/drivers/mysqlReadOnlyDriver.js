"use strict";

function s(value) {
  return String(value ?? "").trim();
}

function positiveInt(value, fallback, max = 10000) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) {
    return fallback;
  }
  return Math.min(n, max);
}

function assertIdentifier(value, label) {
  const out = s(value);

  if (!out) {
    throw new Error(`${label}_REQUIRED`);
  }

  if (!/^[A-Za-z0-9_]+$/.test(out)) {
    throw new Error(`${label}_INVALID_IDENTIFIER`);
  }

  return out;
}

function quoteIdentifier(value, label) {
  return `\`${assertIdentifier(value, label)}\``;
}

function normalizeColumns(columns) {
  if (!Array.isArray(columns) || columns.length === 0) {
    throw new Error("MYSQL_COLUMNS_REQUIRED");
  }

  return columns.map((column, index) =>
    quoteIdentifier(
      column,
      `MYSQL_COLUMN_${index}`
    )
  );
}

function normalizePollSpec(spec = {}) {
  const table =
    quoteIdentifier(
      spec.table,
      "MYSQL_TABLE"
    );

  const schema =
    s(spec.schema)
      ? quoteIdentifier(
          spec.schema,
          "MYSQL_SCHEMA"
        )
      : "";

  const columns =
    normalizeColumns(spec.columns);

  const cursorColumn =
    quoteIdentifier(
      spec.cursorColumn,
      "MYSQL_CURSOR_COLUMN"
    );

  const tieBreakerColumn =
    s(spec.tieBreakerColumn)
      ? quoteIdentifier(
          spec.tieBreakerColumn,
          "MYSQL_TIE_BREAKER_COLUMN"
        )
      : null;

  const limit =
    positiveInt(
      spec.limit,
      500,
      5000
    );

  return {
    table: schema
      ? `${schema}.${table}`
      : table,
    columns,
    cursorColumn,
    tieBreakerColumn,
    limit
  };
}

function normalizeCheckpoint(
  checkpoint,
  hasTieBreaker
) {
  if (
    checkpoint === null ||
    checkpoint === undefined
  ) {
    return null;
  }

  if (
    typeof checkpoint !== "object" ||
    Array.isArray(checkpoint)
  ) {
    throw new Error(
      "MYSQL_CHECKPOINT_INVALID"
    );
  }

  if (
    !Object.prototype.hasOwnProperty.call(
      checkpoint,
      "cursor"
    )
  ) {
    throw new Error(
      "MYSQL_CHECKPOINT_CURSOR_REQUIRED"
    );
  }

  const out = {
    cursor: checkpoint.cursor
  };

  if (hasTieBreaker) {
    if (
      !Object.prototype.hasOwnProperty.call(
        checkpoint,
        "tieBreaker"
      )
    ) {
      throw new Error(
        "MYSQL_CHECKPOINT_TIE_BREAKER_REQUIRED"
      );
    }

    out.tieBreaker =
      checkpoint.tieBreaker;
  }

  return out;
}

function buildSelectQuery(
  normalizedSpec,
  checkpoint
) {
  const {
    table,
    columns,
    cursorColumn,
    tieBreakerColumn,
    limit
  } = normalizedSpec;

  const values = [];

  let whereSql = "";

  if (checkpoint) {
    if (tieBreakerColumn) {
      whereSql =
        `WHERE (` +
        `${cursorColumn} > ? OR ` +
        `(${cursorColumn} = ? AND ` +
        `${tieBreakerColumn} > ?)` +
        `)`;

      values.push(
        checkpoint.cursor,
        checkpoint.cursor,
        checkpoint.tieBreaker
      );
    } else {
      whereSql =
        `WHERE ${cursorColumn} > ?`;

      values.push(
        checkpoint.cursor
      );
    }
  }

  const orderSql =
    tieBreakerColumn
      ? `ORDER BY ${cursorColumn} ASC, ${tieBreakerColumn} ASC`
      : `ORDER BY ${cursorColumn} ASC`;

  const sql = [
    `SELECT ${columns.join(", ")}`,
    `FROM ${table}`,
    whereSql,
    orderSql,
    `LIMIT ${limit}`
  ]
    .filter(Boolean)
    .join(" ");

  return {
    sql,
    values
  };
}

function valueAt(row, column) {
  if (
    !row ||
    typeof row !== "object"
  ) {
    return undefined;
  }

  return row[column];
}

function createMySqlReadOnlyDriver(
  config = {},
  deps = {}
) {
  const spec =
    normalizePollSpec(
      config.poll
    );

  const cursorColumnRaw =
    assertIdentifier(
      config.poll?.cursorColumn,
      "MYSQL_CURSOR_COLUMN"
    );

  const tieBreakerRaw =
    s(config.poll?.tieBreakerColumn)
      ? assertIdentifier(
          config.poll.tieBreakerColumn,
          "MYSQL_TIE_BREAKER_COLUMN"
        )
      : null;

  const connectionFactory =
    deps.connectionFactory;

  if (
    typeof connectionFactory !==
    "function"
  ) {
    throw new Error(
      "MYSQL_CONNECTION_FACTORY_REQUIRED"
    );
  }

  let connection = null;

  return {
    readOnly: true,

    async connect() {
      if (connection) return;

      connection =
        await connectionFactory({
          host: s(config.host),
          port:
            positiveInt(
              config.port,
              3306,
              65535
            ),
          database:
            s(config.database),
          user:
            s(config.user),
          password:
            s(config.password),
          multipleStatements: false
        });

      if (
        !connection ||
        typeof connection.execute !==
          "function" ||
        typeof connection.end !==
          "function"
      ) {
        throw new Error(
          "MYSQL_CONNECTION_CONTRACT_INVALID"
        );
      }
    },

    async poll({ checkpoint } = {}) {
      if (!connection) {
        throw new Error(
          "MYSQL_DRIVER_NOT_CONNECTED"
        );
      }

      const normalizedCheckpoint =
        normalizeCheckpoint(
          checkpoint,
          Boolean(tieBreakerRaw)
        );

      const query =
        buildSelectQuery(
          spec,
          normalizedCheckpoint
        );

      const [rows] =
        await connection.execute(
          query.sql,
          query.values
        );

      if (!Array.isArray(rows)) {
        throw new Error(
          "MYSQL_ROWS_INVALID"
        );
      }

      let nextCheckpoint =
        normalizedCheckpoint;

      if (rows.length > 0) {
        const last =
          rows[rows.length - 1];

        const cursor =
          valueAt(
            last,
            cursorColumnRaw
          );

        if (
          cursor === undefined ||
          cursor === null
        ) {
          throw new Error(
            "MYSQL_CURSOR_VALUE_MISSING"
          );
        }

        nextCheckpoint = {
          cursor
        };

        if (tieBreakerRaw) {
          const tieBreaker =
            valueAt(
              last,
              tieBreakerRaw
            );

          if (
            tieBreaker === undefined ||
            tieBreaker === null
          ) {
            throw new Error(
              "MYSQL_TIE_BREAKER_VALUE_MISSING"
            );
          }

          nextCheckpoint.tieBreaker =
            tieBreaker;
        }
      }

      return {
        records: rows,
        nextCheckpoint
      };
    },

    async close() {
      if (!connection) return;

      const current =
        connection;

      connection = null;

      await current.end();
    }
  };
}

module.exports = {
  normalizePollSpec,
  normalizeCheckpoint,
  buildSelectQuery,
  createMySqlReadOnlyDriver
};
