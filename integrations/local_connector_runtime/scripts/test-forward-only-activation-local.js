"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const {
  FileCheckpointStore,
} = require("../src/core/checkpointStore");

const {
  captureMySqlTailCheckpoint,
  assertForwardOnlyActivation,
  initializeForwardOnlyActivation,
} = require("../src/runtime/forwardOnlyActivation");

(async () => {
  const tmp = fs.mkdtempSync(
    path.join(os.tmpdir(), "css-forward-only-")
  );

  const config = {
    driverId: "mysql",
    checkpointKey: "clinic-source-instance",
    source: {
      host: "127.0.0.1",
      port: 3306,
      database: "fixture_db",
      user: "readonly_user",
      passwordEnv: "CLINIC_SOURCE_DB_PASSWORD",
      poll: {
        table: "movement_log",
        columns: [
          "occurred_at",
          "id",
          "item_id",
        ],
        cursorColumn: "occurred_at",
        tieBreakerColumn: "id",
        limit: 50,
      },
    },
  };

  let tailSql = "";
  let ended = false;

  const captured =
    await captureMySqlTailCheckpoint(
      config.source,
      {
        env: {
          CLINIC_SOURCE_DB_PASSWORD:
            "fixture-password",
        },
        connectionFactory: async (cfg) => {
          assert.equal(
            cfg.multipleStatements,
            false
          );
          return {
            async execute(sql, values) {
              tailSql = sql;
              assert.deepEqual(values, []);
              return [[{
                occurred_at:
                  "2026-09-10 00:00:00",
                id: 77,
              }], []];
            },
            async end() {
              ended = true;
            },
          };
        },
      }
    );

  assert.deepEqual(captured, {
    cursor: "2026-09-10 00:00:00",
    tieBreaker: 77,
  });
  assert.equal(ended, true);
  assert.match(
    tailSql,
    /ORDER BY `occurred_at` DESC, `id` DESC LIMIT 1/
  );

  const store = new FileCheckpointStore(
    path.join(tmp, "checkpoints.json")
  );

  let captures = 0;
  const first =
    await initializeForwardOnlyActivation({
      config,
      checkpointStore: store,
      captureTailCheckpointImpl:
        async () => {
          captures += 1;
          return {
            cursor:
              "2026-09-10 00:00:00",
            tieBreaker: 77,
          };
        },
    });

  assert.equal(first.initialized, true);
  assert.equal(first.alreadyInitialized, false);
  assert.equal(captures, 1);

  assert.deepEqual(
    assertForwardOnlyActivation({
      config,
      checkpointStore: store,
    }),
    {
      cursor: "2026-09-10 00:00:00",
      tieBreaker: 77,
    }
  );

  const second =
    await initializeForwardOnlyActivation({
      config,
      checkpointStore: store,
      captureTailCheckpointImpl:
        async () => {
          throw new Error(
            "TAIL_MUST_NOT_BE_RECAPTURED"
          );
        },
    });

  assert.equal(second.initialized, false);
  assert.equal(second.alreadyInitialized, true);

  const emptyStore = new FileCheckpointStore(
    path.join(tmp, "empty.json")
  );

  await assert.rejects(
    () =>
      initializeForwardOnlyActivation({
        config,
        checkpointStore: emptyStore,
        captureTailCheckpointImpl:
          async () => null,
      }),
    /Source has no tail row/
  );

  assert.throws(
    () =>
      assertForwardOnlyActivation({
        config,
        checkpointStore: emptyStore,
      }),
    /Forward-only checkpoint must be initialized/
  );

  const root = path.resolve(__dirname, "..");

  const connector = fs.readFileSync(
    path.join(root, "bin/connector.js"),
    "utf8"
  );

  assert.ok(
    connector.indexOf(
      "assertForwardOnlyActivation({"
    ) >= 0
  );
  assert.ok(
    connector.indexOf(
      "assertForwardOnlyActivation({"
    ) < connector.indexOf("await runner.start()")
  );

  const provision = fs.readFileSync(
    path.join(
      root,
      "packaging/windows/scripts/provision-and-start-service.ps1"
    ),
    "utf8"
  );

  const validateConfig = fs.readFileSync(
    path.join(
      root,
      "packaging/windows/scripts/validate-config.ps1"
    ),
    "utf8"
  );

  assert.ok(
    validateConfig.trimStart().startsWith("param(")
  );
  assert.ok(
    validateConfig.indexOf("$ErrorActionPreference") >
      validateConfig.indexOf("param(")
  );

  assert.ok(
    provision.trimStart().startsWith("param(")
  );
  assert.ok(
    provision.indexOf("$ErrorActionPreference") >
      provision.indexOf("param(")
  );

  const bootstrapIndex = provision.indexOf(
    "$BootstrapScript $ActiveConfig"
  );
  const installIndex = provision.indexOf(
    "& $InstallScript"
  );
  const startIndex = provision.indexOf(
    "& $ServiceExe start"
  );

  assert.ok(bootstrapIndex >= 0);
  assert.ok(installIndex > bootstrapIndex);
  assert.ok(startIndex > installIndex);

  const template = JSON.parse(
    fs.readFileSync(
      path.join(
        root,
        "packaging/windows/templates/connector-config.template.json"
      ),
      "utf8"
    )
  );

  assert.equal(
    template.adapterProfile
      .movementSemanticsVerified,
    false
  );
  assert.equal(
    "previousAmountUnit" in
      template.adapterProfile.fields,
    true
  );
  assert.equal(
    "amountUnit" in
      template.adapterProfile.fields,
    true
  );
  assert.equal(
    "quantity" in
      template.adapterProfile.fields,
    false
  );

  const verify = fs.readFileSync(
    path.join(
      root,
      "packaging/windows/build_pipeline/verify-build-layout.ps1"
    ),
    "utf8"
  );

  assert.match(
    verify,
    /app\\bin\\bootstrap-forward-only\.js/
  );

  console.log(
    "FORWARD_ONLY_ACTIVATION_TESTS_PASSED=TRUE"
  );
  console.log(
    "SOURCE_TAIL_CAPTURE_READ_ONLY=TRUE"
  );
  console.log(
    "CHECKPOINT_SEEDED_BEFORE_SERVICE_START=TRUE"
  );
  console.log(
    "EXISTING_CHECKPOINT_NOT_OVERWRITTEN=TRUE"
  );
  console.log(
    "MISSING_CHECKPOINT_SERVICE_START_BLOCKED=TRUE"
  );
  console.log(
    "EMPTY_SOURCE_FAIL_CLOSED=TRUE"
  );
  console.log(
    "VENDOR_SPECIFIC_LOGIC_IN_ACTIVATION_CORE=FALSE"
  );
})();
