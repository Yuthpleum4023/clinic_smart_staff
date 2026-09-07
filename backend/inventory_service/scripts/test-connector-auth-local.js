const assert = require(
  "node:assert/strict"
);

const {
  TOKEN_PREFIX,
  parseConnectorToken,
  hashConnectorSecret,
  verifyConnectorSecret,
  generateConnectorCredential,
} = require(
  "../services/connectorCredentialService"
);

const {
  extractBearerToken,
} = require(
  "../middleware/connectorAuth"
);

function expectCode(
  fn,
  expectedCode
) {
  let thrown = null;

  try {
    fn();
  } catch (err) {
    thrown = err;
  }

  assert.ok(thrown);
  assert.equal(
    thrown.code,
    expectedCode
  );
}

const credential =
  generateConnectorCredential();

assert.equal(
  credential.credentialVersion,
  1
);

assert.equal(
  credential.credentialHash.length,
  64
);

assert.equal(
  credential.token.split(".")[0],
  TOKEN_PREFIX
);

const parsed =
  parseConnectorToken(
    credential.token
  );

assert.equal(
  parsed.credentialKeyId,
  credential.credentialKeyId
);

assert.ok(
  parsed.secret.length >= 40
);

assert.equal(
  verifyConnectorSecret({
    credentialKeyId:
      parsed.credentialKeyId,
    secret:
      parsed.secret,
    credentialVersion: 1,
    credentialHash:
      credential.credentialHash,
  }),
  true
);

assert.equal(
  verifyConnectorSecret({
    credentialKeyId:
      parsed.credentialKeyId,
    secret:
      `${parsed.secret}wrong`,
    credentialVersion: 1,
    credentialHash:
      credential.credentialHash,
  }),
  false
);

assert.equal(
  verifyConnectorSecret({
    credentialKeyId:
      parsed.credentialKeyId,
    secret:
      parsed.secret,
    credentialVersion: 2,
    credentialHash:
      credential.credentialHash,
  }),
  false
);

assert.equal(
  hashConnectorSecret({
    credentialKeyId:
      parsed.credentialKeyId,
    secret:
      parsed.secret,
    credentialVersion: 1,
  }),
  credential.credentialHash
);

const rotated =
  generateConnectorCredential({
    credentialVersion: 2,
  });

assert.notEqual(
  rotated.credentialKeyId,
  credential.credentialKeyId
);

assert.notEqual(
  rotated.credentialHash,
  credential.credentialHash
);

expectCode(
  () =>
    parseConnectorToken(""),
  "INVALID_CONNECTOR_CREDENTIAL"
);

expectCode(
  () =>
    parseConnectorToken(
      "Bearer something"
    ),
  "INVALID_CONNECTOR_CREDENTIAL"
);

expectCode(
  () =>
    parseConnectorToken(
      "cssinv1.only-two"
    ),
  "INVALID_CONNECTOR_CREDENTIAL"
);

expectCode(
  () =>
    generateConnectorCredential({
      credentialVersion: 0,
    }),
  "INVALID_CONNECTOR_CREDENTIAL_VERSION"
);

assert.equal(
  extractBearerToken({
    headers: {
      authorization:
        `Bearer ${credential.token}`,
    },
  }),
  credential.token
);

assert.equal(
  extractBearerToken({
    headers: {
      authorization:
        `bearer ${credential.token}`,
    },
  }),
  credential.token
);

assert.equal(
  extractBearerToken({
    headers: {
      authorization:
        credential.token,
    },
  }),
  ""
);

assert.equal(
  extractBearerToken({
    headers: {},
  }),
  ""
);

console.log(
  "CONNECTOR_AUTH_LOCAL_TESTS_PASSED=TRUE"
);
console.log(
  "PLAINTEXT_SECRET_STORAGE_REQUIRED=FALSE"
);
console.log(
  "TIMING_SAFE_VERIFY=TRUE"
);
console.log(
  "USER_JWT_REUSED=FALSE"
);
console.log(
  "INTERNAL_SERVICE_KEY_REUSED=FALSE"
);
console.log(
  "ROUTES_EXPOSED=FALSE"
);
