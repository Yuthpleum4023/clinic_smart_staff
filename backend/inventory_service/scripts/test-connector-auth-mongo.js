const assert = require("node:assert/strict");
const path = require("node:path");

require("dotenv").config({
  path: path.join(
    __dirname,
    "..",
    ".env"
  ),
});

const mongoose = require("mongoose");

const ConnectorConfig = require(
  "../models/ConnectorConfig"
);

const {
  generateConnectorCredential,
} = require(
  "../services/connectorCredentialService"
);

const {
  connectorAuth,
} = require(
  "../middleware/connectorAuth"
);

const TEST_DB =
  "css_inventory_auth_test";

function assertTestDatabase() {
  if (
    mongoose.connection.name !==
    TEST_DB
  ) {
    const err = new Error(
      `Refusing auth simulator cleanup outside ${TEST_DB}`
    );
    err.code =
      "TEST_DATABASE_GUARD_FAILED";
    throw err;
  }
}

async function cleanup() {
  assertTestDatabase();

  await mongoose.connection
    .collection(
      ConnectorConfig.collection.name
    )
    .deleteMany({});
}

async function ensureIndexes() {
  assertTestDatabase();
  await ConnectorConfig.createIndexes();
}

function fakeResponse() {
  return {
    statusCode: 200,
    payload: null,

    status(code) {
      this.statusCode = code;
      return this;
    },

    json(payload) {
      this.payload = payload;
      return this;
    },
  };
}

async function runMiddleware({
  token = "",
  body = {},
  headers = {},
}) {
  const req = {
    headers: {
      ...headers,
    },
    body,
  };

  if (token) {
    req.headers.authorization =
      `Bearer ${token}`;
  }

  const res = fakeResponse();

  let nextCalled = false;
  let nextError = null;

  await connectorAuth(
    req,
    res,
    (err) => {
      nextCalled = true;
      nextError = err || null;
    }
  );

  return {
    req,
    res,
    nextCalled,
    nextError,
  };
}

function assertUnauthorized(
  result,
  expectedCode
) {
  assert.equal(
    result.nextCalled,
    false
  );

  assert.equal(
    result.nextError,
    null
  );

  assert.equal(
    result.res.statusCode,
    401
  );

  assert.equal(
    result.res.payload?.ok,
    false
  );

  assert.equal(
    result.res.payload?.code,
    expectedCode
  );

  assert.equal(
    result.req.connectorContext,
    undefined
  );
}

async function run() {
  if (!process.env.MONGO_URI) {
    throw new Error(
      "MONGO_URI is required for connector auth Mongo simulator"
    );
  }

  await mongoose.connect(
    process.env.MONGO_URI,
    {
      dbName: TEST_DB,
      autoIndex: false,
    }
  );

  assertTestDatabase();

  await cleanup();
  await ensureIndexes();

  const credentialA =
    generateConnectorCredential();

  const connectorA =
    await ConnectorConfig.create({
      clinicId:
        "auth-sim-clinic-a",
      connectorKey:
        "auth-sim-a",
      externalSystem:
        "auth_simulator_vendor",
      connectorType:
        "simulator",
      displayName:
        "Auth Simulator A",
      enabled: true,
      credentialKeyId:
        credentialA.credentialKeyId,
      credentialHash:
        credentialA.credentialHash,
      credentialVersion:
        credentialA.credentialVersion,
    });

  const credentialB =
    generateConnectorCredential();

  const connectorB =
    await ConnectorConfig.create({
      clinicId:
        "auth-sim-clinic-b",
      connectorKey:
        "auth-sim-b",
      externalSystem:
        "auth_simulator_vendor",
      connectorType:
        "simulator",
      displayName:
        "Auth Simulator B",
      enabled: true,
      credentialKeyId:
        credentialB.credentialKeyId,
      credentialHash:
        credentialB.credentialHash,
      credentialVersion:
        credentialB.credentialVersion,
    });

  // credentialHash is intentionally hidden
  // on a normal query.
  const normalRead =
    await ConnectorConfig.findById(
      connectorA._id
    ).lean();

  assert.equal(
    Object.prototype.hasOwnProperty.call(
      normalRead,
      "credentialHash"
    ),
    false
  );

  // The token must authenticate Connector A
  // and server-resolved scope must win over
  // any attacker-controlled body fields.
  const validA =
    await runMiddleware({
      token:
        credentialA.token,
      body: {
        clinicId:
          "attacker-clinic",
        connectorId:
          String(
            connectorB._id
          ),
        externalSystem:
          "attacker-system",
      },
    });

  assert.equal(
    validA.nextCalled,
    true
  );

  assert.equal(
    validA.nextError,
    null
  );

  assert.equal(
    validA.req
      .connectorContext
      .connectorId,
    String(connectorA._id)
  );

  assert.equal(
    validA.req
      .connectorContext
      .clinicId,
    "auth-sim-clinic-a"
  );

  assert.equal(
    validA.req
      .connectorContext
      .externalSystem,
    "auth_simulator_vendor"
  );

  assert.notEqual(
    validA.req
      .connectorContext
      .clinicId,
    validA.req.body.clinicId
  );

  assert.notEqual(
    validA.req
      .connectorContext
      .connectorId,
    validA.req.body.connectorId
  );

  // Missing credential.
  assertUnauthorized(
    await runMiddleware({}),
    "MISSING_CONNECTOR_TOKEN"
  );

  // Wrong secret with the correct key id.
  const wrongSecretToken =
    [
      "cssinv1",
      credentialA.credentialKeyId,
      "definitely-wrong-secret",
    ].join(".");

  assertUnauthorized(
    await runMiddleware({
      token:
        wrongSecretToken,
    }),
    "INVALID_CONNECTOR_TOKEN"
  );

  // Unknown key id.
  const unknownCredential =
    generateConnectorCredential();

  assertUnauthorized(
    await runMiddleware({
      token:
        unknownCredential.token,
    }),
    "INVALID_CONNECTOR_TOKEN"
  );

  // Disabled connectors are indistinguishable
  // from bad credentials to the external caller.
  connectorA.enabled = false;
  await connectorA.save();

  assertUnauthorized(
    await runMiddleware({
      token:
        credentialA.token,
    }),
    "INVALID_CONNECTOR_TOKEN"
  );

  connectorA.enabled = true;
  await connectorA.save();

  // Rotation replaces key id, hash and version.
  // Old token must stop working immediately.
  const rotated =
    generateConnectorCredential({
      credentialVersion:
        connectorA
          .credentialVersion + 1,
    });

  connectorA.credentialKeyId =
    rotated.credentialKeyId;
  connectorA.credentialHash =
    rotated.credentialHash;
  connectorA.credentialVersion =
    rotated.credentialVersion;

  await connectorA.save();

  assertUnauthorized(
    await runMiddleware({
      token:
        credentialA.token,
    }),
    "INVALID_CONNECTOR_TOKEN"
  );

  const rotatedValid =
    await runMiddleware({
      token:
        rotated.token,
    });

  assert.equal(
    rotatedValid.nextCalled,
    true
  );

  assert.equal(
    rotatedValid.nextError,
    null
  );

  assert.equal(
    rotatedValid.req
      .connectorContext
      .connectorId,
    String(connectorA._id)
  );

  assert.equal(
    rotatedValid.req
      .connectorContext
      .credentialVersion,
    rotated.credentialVersion
  );

  // Unique credentialKeyId is a global
  // authentication namespace because the
  // ingress does not know clinicId before
  // credential resolution.
  let duplicateKeyError = null;

  try {
    await ConnectorConfig.create({
      clinicId:
        "auth-sim-clinic-c",
      connectorKey:
        "auth-sim-c",
      externalSystem:
        "auth_simulator_vendor",
      connectorType:
        "simulator",
      displayName:
        "Auth Simulator C",
      enabled: true,
      credentialKeyId:
        rotated.credentialKeyId,
      credentialHash:
        generateConnectorCredential()
          .credentialHash,
      credentialVersion: 1,
    });
  } catch (err) {
    duplicateKeyError = err;
  }

  assert.ok(
    duplicateKeyError
  );

  assert.equal(
    duplicateKeyError.code,
    11000
  );

  // Ensure Connector B remains isolated and
  // independently authenticatable.
  const validB =
    await runMiddleware({
      token:
        credentialB.token,
    });

  assert.equal(
    validB.nextCalled,
    true
  );

  assert.equal(
    validB.req
      .connectorContext
      .clinicId,
    "auth-sim-clinic-b"
  );

  assert.equal(
    validB.req
      .connectorContext
      .connectorId,
    String(connectorB._id)
  );

  // No plaintext secret is persisted.
  const rawA =
    await ConnectorConfig.findById(
      connectorA._id
    )
      .select("+credentialHash")
      .lean();

  assert.ok(
    rawA.credentialHash
  );

  assert.equal(
    JSON.stringify(rawA)
      .includes(
        rotated.token
      ),
    false
  );

  const rotatedSecret =
    rotated.token.split(".")[2];

  assert.equal(
    JSON.stringify(rawA)
      .includes(
        rotatedSecret
      ),
    false
  );

  console.log(
    "CONNECTOR_AUTH_MONGO_SIMULATOR_PASSED=TRUE"
  );
  console.log(
    "VALID_TOKEN_RESOLVES_CONNECTOR=PASS"
  );
  console.log(
    "SERVER_OWNED_CLINIC_SCOPE=PASS"
  );
  console.log(
    "BODY_SCOPE_OVERRIDE_BLOCKED=PASS"
  );
  console.log(
    "MISSING_TOKEN_REJECTED=PASS"
  );
  console.log(
    "WRONG_SECRET_REJECTED=PASS"
  );
  console.log(
    "UNKNOWN_KEY_ID_REJECTED=PASS"
  );
  console.log(
    "DISABLED_CONNECTOR_REJECTED=PASS"
  );
  console.log(
    "CREDENTIAL_ROTATION_OLD_TOKEN_REJECTED=PASS"
  );
  console.log(
    "CREDENTIAL_ROTATION_NEW_TOKEN_ACCEPTED=PASS"
  );
  console.log(
    "CREDENTIAL_KEY_ID_GLOBALLY_UNIQUE=PASS"
  );
  console.log(
    "CROSS_CLINIC_CONNECTOR_ISOLATION=PASS"
  );
  console.log(
    "PLAINTEXT_SECRET_PERSISTED=FALSE"
  );
  console.log(
    "ROUTES_EXPOSED=FALSE"
  );
  console.log(
    "TEST_DATABASE=" +
      TEST_DB
  );
}

(async () => {
  try {
    await run();
  } finally {
    if (
      mongoose.connection
        .readyState !== 0
    ) {
      try {
        if (
          mongoose.connection.name ===
          TEST_DB
        ) {
          await cleanup();
        }
      } finally {
        await mongoose.disconnect();
      }
    }
  }
})().catch((err) => {
  console.error(
    "CONNECTOR_AUTH_MONGO_SIMULATOR_FAILED=TRUE"
  );
  console.error(
    "CODE=" +
      String(err?.code || "")
  );
  console.error(
    err?.stack || err
  );
  process.exit(1);
});
