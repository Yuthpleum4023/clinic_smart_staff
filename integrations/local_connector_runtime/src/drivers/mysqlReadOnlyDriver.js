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

function normalizeTableRef({
  schema,
  table,
  alias,
  schemaFallback = "",
  label = "MYSQL_TABLE",
}) {
  const tableRaw = assertIdentifier(table, label);
  const schemaRaw = s(schema || schemaFallback)
    ? assertIdentifier(schema || schemaFallback, `${label}_SCHEMA`)
    : "";
  const aliasRaw = s(alias)
    ? assertIdentifier(alias, `${label}_ALIAS`)
    : "";

  const qualified = schemaRaw
    ? `\`${schemaRaw}\`.\`${tableRaw}\``
    : `\`${tableRaw}\``;

  return {
    schemaRaw,
    tableRaw,
    aliasRaw,
    sql: aliasRaw
      ? `${qualified} AS \`${aliasRaw}\``
      : qualified,
  };
}

function normalizeJoin(join, index, baseSchema, knownAliases) {
  if (!join || typeof join !== "object" || Array.isArray(join)) {
    throw new Error(`MYSQL_JOIN_${index}_INVALID`);
  }

  const typeRaw = s(join.type || "inner").toLowerCase();
  if (typeRaw !== "inner" && typeRaw !== "left") {
    throw new Error(`MYSQL_JOIN_${index}_TYPE_UNSUPPORTED`);
  }

  const table = normalizeTableRef({
    schema: join.schema,
    table: join.table,
    alias: join.alias,
    schemaFallback: baseSchema,
    label: `MYSQL_JOIN_${index}_TABLE`,
  });

  if (!table.aliasRaw) {
    throw new Error(`MYSQL_JOIN_${index}_ALIAS_REQUIRED`);
  }

  if (knownAliases.has(table.aliasRaw)) {
    throw new Error(`MYSQL_JOIN_${index}_ALIAS_DUPLICATE`);
  }

  const aliasesForOn = new Set([...knownAliases, table.aliasRaw]);

  function normalizeOnRef(ref, side) {
    if (!ref || typeof ref !== "object" || Array.isArray(ref)) {
      throw new Error(`MYSQL_JOIN_${index}_${side}_INVALID`);
    }

    const tableAlias = assertIdentifier(
      ref.tableAlias,
      `MYSQL_JOIN_${index}_${side}_TABLE_ALIAS`
    );

    if (!aliasesForOn.has(tableAlias)) {
      throw new Error(`MYSQL_JOIN_${index}_${side}_UNKNOWN_ALIAS`);
    }

    const column = assertIdentifier(
      ref.column,
      `MYSQL_JOIN_${index}_${side}_COLUMN`
    );

    return {
      tableAlias,
      column,
      sql: `\`${tableAlias}\`.\`${column}\``,
    };
  }

  const left = normalizeOnRef(join.left, "LEFT");
  const right = normalizeOnRef(join.right, "RIGHT");

  knownAliases.add(table.aliasRaw);

  return {
    type: typeRaw,
    table,
    left,
    right,
    sql:
      `${typeRaw === "left" ? "LEFT JOIN" : "INNER JOIN"} ` +
      `${table.sql} ON ${left.sql} = ${right.sql}`,
  };
}

function normalizeColumnSpec(column, index, baseAlias, knownAliases) {
  if (typeof column === "string") {
    const raw = assertIdentifier(column, `MYSQL_COLUMN_${index}`);
    const sql = baseAlias
      ? `\`${baseAlias}\`.\`${raw}\``
      : `\`${raw}\``;

    return {
      outputName: raw,
      sql,
    };
  }

  if (!column || typeof column !== "object" || Array.isArray(column)) {
    throw new Error(`MYSQL_COLUMN_${index}_INVALID`);
  }

  const tableAlias = s(column.tableAlias || baseAlias)
    ? assertIdentifier(
        column.tableAlias || baseAlias,
        `MYSQL_COLUMN_${index}_TABLE_ALIAS`
      )
    : "";

  if (tableAlias && !knownAliases.has(tableAlias)) {
    throw new Error(`MYSQL_COLUMN_${index}_UNKNOWN_ALIAS`);
  }

  const raw = assertIdentifier(
    column.column,
    `MYSQL_COLUMN_${index}_NAME`
  );

  const outputName = s(column.as)
    ? assertIdentifier(column.as, `MYSQL_COLUMN_${index}_AS`)
    : raw;

  const refSql = tableAlias
    ? `\`${tableAlias}\`.\`${raw}\``
    : `\`${raw}\``;

  return {
    outputName,
    sql: `${refSql} AS \`${outputName}\``,
  };
}

function normalizePredicate(predicate, index, baseAlias, knownAliases) {
  if (
    !predicate ||
    typeof predicate !== "object" ||
    Array.isArray(predicate)
  ) {
    throw new Error(`MYSQL_PREDICATE_${index}_INVALID`);
  }

  const operator = s(predicate.operator || "eq").toLowerCase();
  if (operator !== "eq") {
    throw new Error(`MYSQL_PREDICATE_${index}_OPERATOR_UNSUPPORTED`);
  }

  const tableAlias = s(predicate.tableAlias || baseAlias)
    ? assertIdentifier(
        predicate.tableAlias || baseAlias,
        `MYSQL_PREDICATE_${index}_TABLE_ALIAS`
      )
    : "";

  if (tableAlias && !knownAliases.has(tableAlias)) {
    throw new Error(`MYSQL_PREDICATE_${index}_UNKNOWN_ALIAS`);
  }

  const column = assertIdentifier(
    predicate.column,
    `MYSQL_PREDICATE_${index}_COLUMN`
  );

  if (!Object.prototype.hasOwnProperty.call(predicate, "value")) {
    throw new Error(`MYSQL_PREDICATE_${index}_VALUE_REQUIRED`);
  }

  if (
    predicate.value !== null &&
    typeof predicate.value === "object"
  ) {
    throw new Error(`MYSQL_PREDICATE_${index}_VALUE_INVALID`);
  }

  const refSql = tableAlias
    ? `\`${tableAlias}\`.\`${column}\``
    : `\`${column}\``;

  return {
    sql: `${refSql} = ?`,
    value: predicate.value,
  };
}

function normalizePollSpec(spec = {}) {
  const base = normalizeTableRef({
    schema: spec.schema,
    table: spec.table,
    alias: spec.alias,
    label: "MYSQL_TABLE",
  });

  const joinsInput = Array.isArray(spec.joins)
    ? spec.joins
    : [];

  const predicatesInput = Array.isArray(spec.predicates)
    ? spec.predicates
    : [];

  const objectColumns =
    Array.isArray(spec.columns) &&
    spec.columns.some(
      (column) =>
        column &&
        typeof column === "object" &&
        !Array.isArray(column)
    );

  const relational =
    joinsInput.length > 0 ||
    predicatesInput.length > 0 ||
    objectColumns ||
    Boolean(s(spec.cursorTableAlias)) ||
    Boolean(s(spec.tieBreakerTableAlias));

  if (relational && !base.aliasRaw) {
    throw new Error("MYSQL_BASE_ALIAS_REQUIRED");
  }

  const knownAliases = new Set();
  if (base.aliasRaw) {
    knownAliases.add(base.aliasRaw);
  }

  const joins = joinsInput.map((join, index) =>
    normalizeJoin(
      join,
      index,
      base.schemaRaw,
      knownAliases
    )
  );

  if (!Array.isArray(spec.columns) || spec.columns.length === 0) {
    throw new Error("MYSQL_COLUMNS_REQUIRED");
  }

  const columns = spec.columns.map((column, index) =>
    normalizeColumnSpec(
      column,
      index,
      base.aliasRaw,
      knownAliases
    )
  );

  const cursorColumnRaw = assertIdentifier(
    spec.cursorColumn,
    "MYSQL_CURSOR_COLUMN"
  );

  const cursorTableAliasRaw = s(
    spec.cursorTableAlias || base.aliasRaw
  )
    ? assertIdentifier(
        spec.cursorTableAlias || base.aliasRaw,
        "MYSQL_CURSOR_TABLE_ALIAS"
      )
    : "";

  if (
    cursorTableAliasRaw &&
    !knownAliases.has(cursorTableAliasRaw)
  ) {
    throw new Error("MYSQL_CURSOR_UNKNOWN_ALIAS");
  }

  const cursorColumn = cursorTableAliasRaw
    ? `\`${cursorTableAliasRaw}\`.\`${cursorColumnRaw}\``
    : `\`${cursorColumnRaw}\``;

  const tieBreakerColumnRaw = s(spec.tieBreakerColumn)
    ? assertIdentifier(
        spec.tieBreakerColumn,
        "MYSQL_TIE_BREAKER_COLUMN"
      )
    : null;

  const tieBreakerTableAliasRaw =
    tieBreakerColumnRaw &&
    s(spec.tieBreakerTableAlias || base.aliasRaw)
      ? assertIdentifier(
          spec.tieBreakerTableAlias || base.aliasRaw,
          "MYSQL_TIE_BREAKER_TABLE_ALIAS"
        )
      : "";

  if (
    tieBreakerTableAliasRaw &&
    !knownAliases.has(tieBreakerTableAliasRaw)
  ) {
    throw new Error("MYSQL_TIE_BREAKER_UNKNOWN_ALIAS");
  }

  const tieBreakerColumn = tieBreakerColumnRaw
    ? (
        tieBreakerTableAliasRaw
          ? `\`${tieBreakerTableAliasRaw}\`.\`${tieBreakerColumnRaw}\``
          : `\`${tieBreakerColumnRaw}\``
      )
    : null;

  const predicates = predicatesInput.map((predicate, index) =>
    normalizePredicate(
      predicate,
      index,
      base.aliasRaw,
      knownAliases
    )
  );

  const limit = positiveInt(
    spec.limit,
    500,
    5000
  );

  const outputNames = new Set(
    columns.map((column) => column.outputName)
  );

  if (!outputNames.has(cursorColumnRaw)) {
    throw new Error("MYSQL_CURSOR_COLUMN_MUST_BE_SELECTED");
  }

  if (
    tieBreakerColumnRaw &&
    !outputNames.has(tieBreakerColumnRaw)
  ) {
    throw new Error(
      "MYSQL_TIE_BREAKER_COLUMN_MUST_BE_SELECTED"
    );
  }

  const fromSql = [
    base.sql,
    ...joins.map((join) => join.sql),
  ].join(" ");

  return {
    table: base.sql,
    fromSql,
    columns: columns.map((column) => column.sql),
    cursorColumn,
    cursorColumnRaw,
    tieBreakerColumn,
    tieBreakerColumnRaw,
    predicates,
    limit,
    relational,
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

function buildPredicateParts(normalizedSpec) {
  return {
    sqlParts: normalizedSpec.predicates.map(
      (predicate) => predicate.sql
    ),
    values: normalizedSpec.predicates.map(
      (predicate) => predicate.value
    ),
  };
}

function buildSelectQuery(
  normalizedSpec,
  checkpoint
) {
  const {
    fromSql,
    columns,
    cursorColumn,
    tieBreakerColumn,
    limit
  } = normalizedSpec;

  const predicateParts =
    buildPredicateParts(normalizedSpec);

  const whereParts =
    [...predicateParts.sqlParts];

  const values =
    [...predicateParts.values];

  if (checkpoint) {
    if (tieBreakerColumn) {
      whereParts.push(
        `(` +
        `${cursorColumn} > ? OR ` +
        `(${cursorColumn} = ? AND ` +
        `${tieBreakerColumn} > ?)` +
        `)`
      );

      values.push(
        checkpoint.cursor,
        checkpoint.cursor,
        checkpoint.tieBreaker
      );
    } else {
      whereParts.push(
        `${cursorColumn} > ?`
      );

      values.push(
        checkpoint.cursor
      );
    }
  }

  const whereSql = whereParts.length
    ? `WHERE ${whereParts.join(" AND ")}`
    : "";

  const orderSql =
    tieBreakerColumn
      ? `ORDER BY ${cursorColumn} ASC, ${tieBreakerColumn} ASC`
      : `ORDER BY ${cursorColumn} ASC`;

  const sql = [
    `SELECT ${columns.join(", ")}`,
    `FROM ${fromSql}`,
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

function buildTailQuery(normalizedSpec) {
  const {
    fromSql,
    cursorColumn,
    cursorColumnRaw,
    tieBreakerColumn,
    tieBreakerColumnRaw,
  } = normalizedSpec;

  const predicateParts =
    buildPredicateParts(normalizedSpec);

  const selectSql = tieBreakerColumn
    ? [
        `${cursorColumn} AS \`${cursorColumnRaw}\``,
        `${tieBreakerColumn} AS \`${tieBreakerColumnRaw}\``,
      ].join(", ")
    : `${cursorColumn} AS \`${cursorColumnRaw}\``;

  const whereSql = predicateParts.sqlParts.length
    ? `WHERE ${predicateParts.sqlParts.join(" AND ")}`
    : "";

  const orderSql = tieBreakerColumn
    ? `ORDER BY ${cursorColumn} DESC, ${tieBreakerColumn} DESC`
    : `ORDER BY ${cursorColumn} DESC`;

  const sql = [
    `SELECT ${selectSql}`,
    `FROM ${fromSql}`,
    whereSql,
    orderSql,
    "LIMIT 1",
  ]
    .filter(Boolean)
    .join(" ");

  return {
    sql,
    values: predicateParts.values,
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
    spec.cursorColumnRaw;

  const tieBreakerRaw =
    spec.tieBreakerColumnRaw;

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
  buildTailQuery,
  createMySqlReadOnlyDriver
};
