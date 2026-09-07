const crypto = require("crypto");

const TOKEN_PREFIX = "cssinv1";
const KEY_ID_BYTES = 12;
const SECRET_BYTES = 32;
const HASH_BYTES = 32;

function s(value) {
  return String(value ?? "").trim();
}

function credentialError(
  message,
  code = "INVALID_CONNECTOR_CREDENTIAL",
  status = 401
) {
  const err = new Error(message);
  err.code = code;
  err.status = status;
  return err;
}

function positiveVersion(value) {
  const n = Number(value);

  if (
    !Number.isSafeInteger(n) ||
    n < 1
  ) {
    throw credentialError(
      "Invalid connector credential version",
      "INVALID_CONNECTOR_CREDENTIAL_VERSION",
      400
    );
  }

  return n;
}

function randomBase64Url(bytes) {
  return crypto
    .randomBytes(bytes)
    .toString("base64url");
}

function parseConnectorToken(tokenRaw) {
  const token = s(tokenRaw);
  const parts = token.split(".");

  if (
    parts.length !== 3 ||
    parts[0] !== TOKEN_PREFIX ||
    !s(parts[1]) ||
    !s(parts[2])
  ) {
    throw credentialError(
      "Invalid connector credential"
    );
  }

  return {
    credentialKeyId: parts[1],
    secret: parts[2],
  };
}

function hashConnectorSecret({
  credentialKeyId,
  secret,
  credentialVersion = 1,
}) {
  const keyId = s(credentialKeyId);
  const secretValue = s(secret);
  const version =
    positiveVersion(
      credentialVersion
    );

  if (!keyId || !secretValue) {
    throw credentialError(
      "Invalid connector credential material",
      "INVALID_CONNECTOR_CREDENTIAL_MATERIAL",
      400
    );
  }

  return crypto
    .createHash("sha256")
    .update(
      [
        "clinic-smart-staff",
        "inventory-connector",
        "credential-v1",
        String(version),
        keyId,
        secretValue,
      ].join("\0"),
      "utf8"
    )
    .digest("hex");
}

function safeHashEqual(
  expectedHashRaw,
  actualHashRaw
) {
  const expected =
    s(expectedHashRaw);
  const actual =
    s(actualHashRaw);

  if (
    expected.length !==
      HASH_BYTES * 2 ||
    actual.length !==
      HASH_BYTES * 2
  ) {
    return false;
  }

  let expectedBuffer;
  let actualBuffer;

  try {
    expectedBuffer =
      Buffer.from(
        expected,
        "hex"
      );
    actualBuffer =
      Buffer.from(
        actual,
        "hex"
      );
  } catch (_) {
    return false;
  }

  if (
    expectedBuffer.length !==
      HASH_BYTES ||
    actualBuffer.length !==
      HASH_BYTES
  ) {
    return false;
  }

  return crypto.timingSafeEqual(
    expectedBuffer,
    actualBuffer
  );
}

function verifyConnectorSecret({
  credentialKeyId,
  secret,
  credentialVersion = 1,
  credentialHash,
}) {
  let actualHash = "";

  try {
    actualHash =
      hashConnectorSecret({
        credentialKeyId,
        secret,
        credentialVersion,
      });
  } catch (_) {
    return false;
  }

  return safeHashEqual(
    credentialHash,
    actualHash
  );
}

function generateConnectorCredential({
  credentialVersion = 1,
} = {}) {
  const version =
    positiveVersion(
      credentialVersion
    );

  const credentialKeyId =
    randomBase64Url(
      KEY_ID_BYTES
    );

  const secret =
    randomBase64Url(
      SECRET_BYTES
    );

  const credentialHash =
    hashConnectorSecret({
      credentialKeyId,
      secret,
      credentialVersion:
        version,
    });

  const token = [
    TOKEN_PREFIX,
    credentialKeyId,
    secret,
  ].join(".");

  return {
    token,
    credentialKeyId,
    credentialHash,
    credentialVersion:
      version,
  };
}

module.exports = {
  TOKEN_PREFIX,
  parseConnectorToken,
  hashConnectorSecret,
  verifyConnectorSecret,
  generateConnectorCredential,
};
