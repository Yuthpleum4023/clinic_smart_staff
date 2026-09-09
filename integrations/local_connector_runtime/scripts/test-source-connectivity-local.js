"use strict";

const assert = require("assert");

const {
  requireSourceConfig,
  checkMySqlSourceConnectivity
} = require(
  "../src/connectivity/mysqlSourceConnectivity"
);

(async () => {
  assert.throws(
    () =>
      requireSourceConfig({
        host: "",
        database: "FD5_5",
        user: "readonly",
        passwordEnv:
          "CLINIC_SOURCE_DB_PASSWORD"
      }),
    /SOURCE_CONNECTIVITY_HOST_REQUIRED/
  );

  assert.throws(
    () =>
      requireSourceConfig({
        host: "10.0.0.10",
        database: "FD5_5",
        user: "",
        passwordEnv:
          "CLINIC_SOURCE_DB_PASSWORD"
      }),
    /SOURCE_CONNECTIVITY_USER_REQUIRED/
  );

  let capturedConfig = null;
  let pingCount = 0;
  let closeCount = 0;

  const result =
    await checkMySqlSourceConnectivity(
      {
        host: "10.0.0.10",
        port: 3306,
        database: "FD5_5",
        user: "readonly_user",
        passwordEnv:
          "CLINIC_SOURCE_DB_PASSWORD"
      },
      {
        env: {
          CLINIC_SOURCE_DB_PASSWORD:
            "fixture-secret"
        },

        async connectionFactory(
          config
        ) {
          capturedConfig = {
            ...config
          };

          return {
            async ping() {
              pingCount += 1;
            },

            async end() {
              closeCount += 1;
            }
          };
        }
      }
    );

  assert.equal(
    result.ok,
    true
  );

  assert.equal(
    result.database,
    "FD5_5"
  );

  assert.equal(
    result.businessRowsRead,
    false
  );

  assert.equal(
    result.semanticMappingPerformed,
    false
  );

  assert.equal(
    result.adapterActivated,
    false
  );

  assert.equal(
    result.stockAuthorityUsed,
    false
  );

  assert.equal(
    result.clinicScopeAuthorityUsed,
    false
  );

  assert.equal(
    result.credentialsExposed,
    false
  );

  assert.equal(
    capturedConfig.password,
    "fixture-secret"
  );

  assert.equal(
    capturedConfig.multipleStatements,
    false
  );

  assert.equal(
    pingCount,
    1
  );

  assert.equal(
    closeCount,
    1
  );

  /*
   * The connection path must not require:
   * - connector token
   * - adapter profile
   * - polling schema
   * - semantic mapping
   */
  assert.equal(
    "adapterProfile" in
      capturedConfig,
    false
  );

  assert.equal(
    "poll" in capturedConfig,
    false
  );

  assert.equal(
    "connectorToken" in
      capturedConfig,
    false
  );

  console.log(
    "FD_SOURCE_CONNECTIVITY_TESTS_PASSED=TRUE"
  );
  console.log(
    "REAL_NETWORK_CONNECTION_ATTEMPTED=FALSE"
  );
  console.log(
    "CONNECTIVITY_INDEPENDENT_OF_ADAPTER=TRUE"
  );
  console.log(
    "CONNECTIVITY_INDEPENDENT_OF_BACKEND_TOKEN=TRUE"
  );
  console.log(
    "BUSINESS_ROWS_READ=FALSE"
  );
  console.log(
    "SEMANTIC_MAPPING_PERFORMED=FALSE"
  );
  console.log(
    "DB_PASSWORD_ENV_BOUNDARY=TRUE"
  );
  console.log(
    "MULTIPLE_STATEMENTS_ENABLED=FALSE"
  );
})();
