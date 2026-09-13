"use strict";

const assert = require("assert");

const {
  mysqlConnectionFactory,
} = require("../src/runtime/mysqlConnectionFactory");

(async () => {
  let createConfig = null;
  let queryCount = 0;
  let executeCount = 0;
  let endCount = 0;

  const rawConnection = {
    async query(sql, values) {
      queryCount += 1;
      assert.equal(sql, "SELECT ? AS value");
      assert.deepEqual(values, [7]);
      return [[{ value: 7 }], []];
    },
    async execute() {
      executeCount += 1;
      throw new Error("PREPARED_STATEMENT_PROTOCOL_MUST_NOT_BE_USED");
    },
    async ping() {},
    async end() {
      endCount += 1;
    },
  };

  const connection = await mysqlConnectionFactory(
    {
      host: "legacy-mysql",
      port: 3306,
      database: "verified_db",
      user: "readonly",
      password: "fixture-secret",
    },
    {
      mysqlModule: {
        async createConnection(config) {
          createConfig = config;
          return rawConnection;
        },
      },
    }
  );

  const [rows] = await connection.query("SELECT ? AS value", [7]);
  await connection.end();

  assert.deepEqual(rows, [{ value: 7 }]);
  assert.equal(queryCount, 1);
  assert.equal(executeCount, 0);
  assert.equal(endCount, 1);
  assert.equal(createConfig.multipleStatements, false);
  assert.equal("execute" in connection, false);

  console.log("MYSQL_LEGACY_TEXT_PROTOCOL_TESTS_PASSED=TRUE");
  console.log("SERVER_PREPARED_STATEMENT_PROTOCOL_USED=FALSE");
  console.log("BOUND_QUERY_VALUES_PRESERVED=TRUE");
  console.log("MULTIPLE_STATEMENTS_ENABLED=FALSE");
})();
