const ConnectorConfig = require(
  "../models/ConnectorConfig"
);

const {
  parseConnectorToken,
  verifyConnectorSecret,
} = require(
  "../services/connectorCredentialService"
);

const {
  s,
  lower,
} = require("../utils/strings");

function extractBearerToken(req) {
  const raw =
    s(req.headers?.authorization);

  if (!raw) return "";

  const parts =
    raw.split(" ").filter(Boolean);

  if (
    parts.length !== 2 ||
    lower(parts[0]) !==
      "bearer"
  ) {
    return "";
  }

  return s(parts[1]);
}

function unauthorized(
  res,
  code,
  message
) {
  return res
    .status(401)
    .json({
      ok: false,
      code,
      message,
    });
}

async function connectorAuth(
  req,
  res,
  next
) {
  try {
    const token =
      extractBearerToken(req);

    if (!token) {
      return unauthorized(
        res,
        "MISSING_CONNECTOR_TOKEN",
        "Missing connector credential"
      );
    }

    let parsed;

    try {
      parsed =
        parseConnectorToken(
          token
        );
    } catch (_) {
      return unauthorized(
        res,
        "INVALID_CONNECTOR_TOKEN",
        "Invalid connector credential"
      );
    }

    const connector =
      await ConnectorConfig
        .findOne({
          credentialKeyId:
            parsed.credentialKeyId,
          enabled: true,
        })
        .select(
          "+credentialHash"
        );

    if (
      !connector ||
      !s(connector.credentialHash)
    ) {
      return unauthorized(
        res,
        "INVALID_CONNECTOR_TOKEN",
        "Invalid connector credential"
      );
    }

    const ok =
      verifyConnectorSecret({
        credentialKeyId:
          parsed.credentialKeyId,
        secret:
          parsed.secret,
        credentialVersion:
          connector.credentialVersion,
        credentialHash:
          connector.credentialHash,
      });

    if (!ok) {
      return unauthorized(
        res,
        "INVALID_CONNECTOR_TOKEN",
        "Invalid connector credential"
      );
    }

    const clinicId =
      s(connector.clinicId);

    const externalSystem =
      s(
        connector.externalSystem
      );

    if (
      !clinicId ||
      !externalSystem
    ) {
      const err = new Error(
        "Connector scope is incomplete"
      );
      err.status = 500;
      err.code =
        "CONNECTOR_SCOPE_INVALID";
      return next(err);
    }

    req.connectorContext = {
      connectorId:
        String(connector._id),
      clinicId,
      externalSystem,
      connectorKey:
        s(connector.connectorKey),
      connectorType:
        s(connector.connectorType),
      displayName:
        s(connector.displayName),
      credentialVersion:
        Number(
          connector.credentialVersion
        ),
    };

    return next();
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  connectorAuth,
  extractBearerToken,
};
