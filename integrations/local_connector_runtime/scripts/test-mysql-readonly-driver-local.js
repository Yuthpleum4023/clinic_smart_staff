"use strict";

const assert = require("assert");

const {
  normalizePollSpec,
  buildSelectQuery,
  createMySqlReadOnlyDriver
} = require(
  "../src/drivers/mysqlReadOnlyDriver"
);

(async () => {
  const spec =
    normalizePollSpec({
      schema: "clinic_db",
      table: "dispense_lines",
      columns: [
        "event_id",
        "line_id",
        "item_id",
        "qty",
        "unit",
        "occurred_at"
      ],
      cursorColumn:
        "occurred_at",
      tieBreakerColumn:
        "line_id",
      limit: 250
    });

  const initial =
    buildSelectQuery(
      spec,
      null
    );

  assert.match(
    initial.sql,
    /^SELECT /
  );

  assert.equal(
    initial.values.length,
    0
  );

  assert.equal(
    initial.sql.includes(
      "UPDATE"
    ),
    false
  );

  assert.equal(
    initial.sql.includes(
      "DELETE"
    ),
    false
  );

  assert.equal(
    initial.sql.includes(
      "INSERT"
    ),
    false
  );

  const resumed =
    buildSelectQuery(
      spec,
      {
        cursor:
          "2026-09-08T01:00:00Z",
        tieBreaker:
          100
      }
    );

  assert.equal(
    resumed.values.length,
    3
  );

  assert.throws(
    () =>
      normalizePollSpec({
        table:
          "items; DROP TABLE items",
        columns: ["id"],
        cursorColumn: "id"
      }),
    /INVALID_IDENTIFIER/
  );

  let createdConfig = null;
  let executedSql = null;
  let executedValues = null;
  let closed = false;

  const driver =
    createMySqlReadOnlyDriver(
      {
        host: "127.0.0.1",
        port: 3306,
        database: "clinic_db",
        user: "readonly_user",
        password: "not-persisted-here",
        poll: {
          table:
            "dispense_lines",
          columns: [
            "event_id",
            "line_id",
            "item_id",
            "qty",
            "unit",
            "occurred_at"
          ],
          cursorColumn:
            "occurred_at",
          tieBreakerColumn:
            "line_id",
          limit: 100
        }
      },
      {
        async connectionFactory(
          config
        ) {
          createdConfig =
            config;

          return {
            async execute(
              sql,
              values
            ) {
              executedSql = sql;
              executedValues =
                values;

              return [
                [
                  {
                    event_id:
                      "evt-1",
                    line_id: 9,
                    item_id:
                      "item-1",
                    qty: 2,
                    unit: "piece",
                    occurred_at:
                      "2026-09-08T03:00:00Z"
                  }
                ],
                []
              ];
            },

            async end() {
              closed = true;
            }
          };
        }
      }
    );

  assert.equal(
    driver.readOnly,
    true
  );

  await driver.connect();

  assert.equal(
    createdConfig.multipleStatements,
    false
  );

  const result =
    await driver.poll({
      checkpoint: {
        cursor:
          "2026-09-08T02:00:00Z",
        tieBreaker: 1
      }
    });

  assert.match(
    executedSql,
    /^SELECT /
  );

  assert.equal(
    executedSql.includes(
      ";"
    ),
    false
  );

  assert.deepEqual(
    executedValues,
    [
      "2026-09-08T02:00:00Z",
      "2026-09-08T02:00:00Z",
      1
    ]
  );

  assert.equal(
    result.records.length,
    1
  );

  assert.deepEqual(
    result.nextCheckpoint,
    {
      cursor:
        "2026-09-08T03:00:00Z",
      tieBreaker: 9
    }
  );

  await driver.close();

  assert.equal(
    closed,
    true
  );

  console.log(
    "GENERIC_MYSQL_READONLY_DRIVER_TESTS_PASSED=TRUE"
  );
  console.log(
    "ARBITRARY_SQL_ACCEPTED=FALSE"
  );
  console.log(
    "WRITE_SQL_CONSTRUCTED=FALSE"
  );
  console.log(
    "MULTIPLE_STATEMENTS_ENABLED=FALSE"
  );
  console.log(
    "STRUCTURED_POLL_SPEC=TRUE"
  );
  console.log(
    "CURSOR_CHECKPOINT=TRUE"
  );
  console.log(
    "TIE_BREAKER_CHECKPOINT=TRUE"
  );
  console.log(
    "VENDOR_SPECIFIC_LOGIC=FALSE"
  );
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
