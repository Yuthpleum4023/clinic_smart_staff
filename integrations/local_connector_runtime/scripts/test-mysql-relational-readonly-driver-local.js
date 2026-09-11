"use strict";

const assert = require("assert");

const {
  normalizePollSpec,
  buildSelectQuery,
  buildTailQuery,
  createMySqlReadOnlyDriver,
} = require("../src/drivers/mysqlReadOnlyDriver");

(async () => {
  const poll = {
    schema: "clinic_db",
    table: "dispense_lines",
    alias: "d",
    columns: [
      { tableAlias: "d", column: "id", as: "id" },
      { tableAlias: "d", column: "item_id", as: "item_id" },
      { tableAlias: "d", column: "qty", as: "qty" },
      { tableAlias: "h", column: "doc_type", as: "doc_type" },
    ],
    joins: [
      {
        type: "inner",
        table: "dispense_headers",
        alias: "h",
        left: { tableAlias: "d", column: "xfer_no" },
        right: { tableAlias: "h", column: "xfer_no" },
      },
    ],
    predicates: [
      {
        tableAlias: "h",
        column: "doc_type",
        operator: "eq",
        value: "W-Sale",
      },
    ],
    cursorColumn: "id",
    cursorTableAlias: "d",
    limit: 100,
  };

  const spec = normalizePollSpec(poll);

  const resumed = buildSelectQuery(
    spec,
    { cursor: 250 }
  );

  assert.match(resumed.sql, /^SELECT /);
  assert.match(
    resumed.sql,
    /INNER JOIN `clinic_db`\.`dispense_headers` AS `h` ON `d`\.`xfer_no` = `h`\.`xfer_no`/
  );
  assert.match(
    resumed.sql,
    /WHERE `h`\.`doc_type` = \? AND `d`\.`id` > \?/
  );
  assert.deepEqual(
    resumed.values,
    ["W-Sale", 250]
  );
  assert.equal(resumed.sql.includes(";"), false);
  assert.equal(resumed.sql.includes("UPDATE"), false);
  assert.equal(resumed.sql.includes("DELETE"), false);
  assert.equal(resumed.sql.includes("INSERT"), false);

  const tail = buildTailQuery(spec);

  assert.match(
    tail.sql,
    /^SELECT `d`\.`id` AS `id` FROM /
  );
  assert.match(
    tail.sql,
    /INNER JOIN `clinic_db`\.`dispense_headers` AS `h`/
  );
  assert.match(
    tail.sql,
    /WHERE `h`\.`doc_type` = \?/
  );
  assert.match(
    tail.sql,
    /ORDER BY `d`\.`id` DESC LIMIT 1$/
  );
  assert.deepEqual(
    tail.values,
    ["W-Sale"]
  );

  assert.throws(
    () =>
      normalizePollSpec({
        ...poll,
        joins: [
          {
            type: "inner",
            table: "dispense_headers;DROP",
            alias: "h",
            left: { tableAlias: "d", column: "xfer_no" },
            right: { tableAlias: "h", column: "xfer_no" },
          },
        ],
      }),
    /INVALID_IDENTIFIER/
  );

  assert.throws(
    () =>
      normalizePollSpec({
        ...poll,
        predicates: [
          {
            tableAlias: "h",
            column: "doc_type",
            operator: "raw_sql",
            value: "W-Sale",
          },
        ],
      }),
    /OPERATOR_UNSUPPORTED/
  );

  let executedSql = null;
  let executedValues = null;

  const driver = createMySqlReadOnlyDriver(
    {
      host: "127.0.0.1",
      port: 3306,
      database: "clinic_db",
      user: "readonly_user",
      password: "test-only",
      poll,
    },
    {
      async connectionFactory() {
        return {
          async execute(sql, values) {
            executedSql = sql;
            executedValues = values;
            return [
              [
                {
                  id: 251,
                  item_id: "159",
                  qty: 1,
                  doc_type: "W-Sale",
                },
              ],
              [],
            ];
          },
          async end() {},
        };
      },
    }
  );

  await driver.connect();

  const result = await driver.poll({
    checkpoint: { cursor: 250 },
  });

  assert.equal(result.records.length, 1);
  assert.deepEqual(
    result.nextCheckpoint,
    { cursor: 251 }
  );
  assert.deepEqual(
    executedValues,
    ["W-Sale", 250]
  );
  assert.match(
    executedSql,
    /INNER JOIN/
  );

  await driver.close();

  console.log("GENERIC_MYSQL_RELATIONAL_READONLY_TESTS_PASSED=TRUE");
  console.log("ARBITRARY_SQL_ACCEPTED=FALSE");
  console.log("STRUCTURED_JOIN_SUPPORTED=TRUE");
  console.log("PARAMETERIZED_PREDICATES=TRUE");
  console.log("TAIL_QUERY_SHARES_RELATIONAL_FILTER=TRUE");
  console.log("VENDOR_SPECIFIC_LOGIC=FALSE");
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
