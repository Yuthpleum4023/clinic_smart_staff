const {
  processConsumptionEvent,
} = require(
  "../services/integrationProcessingService"
);

const {
  recordConnectorSeen,
  recordConnectorSuccess,
  recordConnectorError,
} = require(
  "../services/integrationOperationalService"
);

function s(value) {
  return String(value ?? "").trim();
}

async function consume(
  req,
  res,
  next
) {
  let connectorId = "";

  try {
    connectorId =
      s(
        req.connectorContext
          ?.connectorId
      );

    if (!connectorId) {
      const err = new Error(
        "Connector authentication context is required"
      );
      err.status = 401;
      err.code =
        "CONNECTOR_AUTH_CONTEXT_REQUIRED";
      throw err;
    }

    // Operational telemetry is best-effort and
    // must never alter ingestion authority.
    try {
      await recordConnectorSeen({
        connectorId,
      });
    } catch (_) {}

    // Scope is server-owned.
    //
    // No clinicId, connectorId,
    // externalSystem or reprocess flag
    // from the request body is used
    // as authority here.
    const result =
      await processConsumptionEvent({
        connectorId,
        input:
          req.body &&
          typeof req.body ===
            "object"
            ? req.body
            : {},
      });

    try {
      await recordConnectorSuccess({
        connectorId,
      });
    } catch (_) {}

    return res
      .status(
        result?.idempotentReplay
          ? 200
          : 201
      )
      .json({
        ok: true,
        action:
          "external_consumption_processed",
        data: result,
      });
  } catch (err) {
    if (connectorId) {
      try {
        await recordConnectorError({
          connectorId,
          errorCode:
            err?.code,
        });
      } catch (_) {}
    }

    return next(err);
  }
}

module.exports = {
  consume,
};
