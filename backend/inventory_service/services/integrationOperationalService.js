const mongoose = require("mongoose");

const ConnectorConfig = require("../models/ConnectorConfig");
const IntegrationEvent = require("../models/IntegrationEvent");

const {
  processConsumptionEvent,
} = require("./integrationProcessingService");

const { s } = require("../utils/strings");

const EVENT_STATUSES = new Set(
  IntegrationEvent.EVENT_STATUSES || [
    "received",
    "processing",
    "applied",
    "blocked",
    "rejected",
  ]
);

function codedError(
  message,
  code,
  status = 400,
  details = null
) {
  const err = new Error(message);
  err.code = code;
  err.status = status;

  if (details) {
    err.details = details;
  }

  return err;
}

function objectId(value, label) {
  const raw = s(value);

  if (!mongoose.Types.ObjectId.isValid(raw)) {
    throw codedError(
      `${label} is invalid`,
      "INVALID_OBJECT_ID",
      400,
      { field: label }
    );
  }

  return raw;
}

function safeLimit(value) {
  if (value === undefined || value === null || value === "") {
    return 50;
  }

  const n = Number(value);

  if (!Number.isSafeInteger(n) || n < 1 || n > 100) {
    throw codedError(
      "limit must be an integer between 1 and 100",
      "INVALID_LIMIT",
      400
    );
  }

  return n;
}

function safeStatus(value) {
  const status = s(value);

  if (!status) {
    return "";
  }

  if (!EVENT_STATUSES.has(status)) {
    throw codedError(
      "status is invalid",
      "INVALID_INTEGRATION_EVENT_STATUS",
      400,
      { status }
    );
  }

  return status;
}

async function resolveConnectorForClinic({
  clinicId,
  connectorId,
}) {
  const id = objectId(
    connectorId,
    "connectorId"
  );

  const connector = await ConnectorConfig.findOne({
    _id: id,
    clinicId: s(clinicId),
  }).lean();

  if (!connector) {
    throw codedError(
      "Connector not found",
      "CONNECTOR_NOT_FOUND",
      404
    );
  }

  return connector;
}

function connectorHealthView(connector) {
  return {
    _id: connector._id,
    clinicId: connector.clinicId,
    connectorKey: connector.connectorKey,
    externalSystem: connector.externalSystem,
    connectorType: connector.connectorType,
    displayName: connector.displayName,
    enabled: connector.enabled,
    credentialVersion: connector.credentialVersion,
    hasCredential: !!s(connector.credentialKeyId),
    lastSeenAt: connector.lastSeenAt || null,
    lastSuccessfulSyncAt:
      connector.lastSuccessfulSyncAt || null,
    lastErrorAt: connector.lastErrorAt || null,
    lastErrorCode: s(connector.lastErrorCode),
    createdAt: connector.createdAt,
    updatedAt: connector.updatedAt,
  };
}

function hasMetadata(value) {
  return !!(
    value &&
    typeof value === "object" &&
    Object.keys(value).length > 0
  );
}

function eventView(event) {
  return {
    _id: event._id,
    clinicId: event.clinicId,
    connectorId: event.connectorId,
    externalSystem: event.externalSystem,
    externalEventId: event.externalEventId,
    externalLineId: event.externalLineId,
    externalItemId: event.externalItemId,
    externalUnit: event.externalUnit,
    externalQuantity: event.externalQuantity,
    eventType: event.eventType,
    occurredAt: event.occurredAt,
    referenceType: event.referenceType,
    referenceNo: event.referenceNo,
    hasSourceMetadata: hasMetadata(
      event.sourceMetadata
    ),
    status: event.status,
    processingAttempts: event.processingAttempts,
    lastAttemptAt: event.lastAttemptAt || null,
    mappingId: event.mappingId || null,
    stockItemId: event.stockItemId || null,
    normalizedQuantity:
      event.normalizedQuantity ?? null,
    stockMovementId: event.stockMovementId || null,
    errorCode: s(event.errorCode),
    errorMessage: s(event.errorMessage),
    appliedAt: event.appliedAt || null,
    createdAt: event.createdAt,
    updatedAt: event.updatedAt,
  };
}

function eventInputFromStored(event) {
  const occurredAt =
    event.occurredAt instanceof Date
      ? event.occurredAt.toISOString()
      : event.occurredAt;

  return {
    externalEventId: event.externalEventId,
    externalLineId: event.externalLineId,
    externalItemId: event.externalItemId,
    quantity: event.externalQuantity,
    unit: event.externalUnit,
    eventType: event.eventType,
    occurredAt,
    referenceType: event.referenceType,
    referenceNo: event.referenceNo,
    metadata:
      event.sourceMetadata &&
      typeof event.sourceMetadata === "object"
        ? event.sourceMetadata
        : {},
  };
}

async function recordConnectorSeen({
  connectorId,
}) {
  if (!mongoose.Types.ObjectId.isValid(
    String(connectorId || "")
  )) {
    return;
  }

  await ConnectorConfig.updateOne(
    {
      _id: connectorId,
      enabled: true,
    },
    {
      $set: {
        lastSeenAt: new Date(),
      },
    }
  );
}

async function recordConnectorSuccess({
  connectorId,
}) {
  if (!mongoose.Types.ObjectId.isValid(
    String(connectorId || "")
  )) {
    return;
  }

  const now = new Date();

  await ConnectorConfig.updateOne(
    {
      _id: connectorId,
    },
    {
      $set: {
        lastSeenAt: now,
        lastSuccessfulSyncAt: now,
        lastErrorCode: "",
      },
    }
  );
}

async function recordConnectorError({
  connectorId,
  errorCode,
}) {
  if (!mongoose.Types.ObjectId.isValid(
    String(connectorId || "")
  )) {
    return;
  }

  const now = new Date();

  await ConnectorConfig.updateOne(
    {
      _id: connectorId,
    },
    {
      $set: {
        lastSeenAt: now,
        lastErrorAt: now,
        lastErrorCode:
          s(errorCode) ||
          "INTEGRATION_REQUEST_FAILED",
      },
    }
  );
}

async function getConnectorHealth({
  clinicId,
  connectorId,
}) {
  const connector = await resolveConnectorForClinic({
    clinicId,
    connectorId,
  });

  const match = {
    clinicId: s(clinicId),
    connectorId: connector._id,
  };

  const [
    total,
    received,
    processing,
    applied,
    blocked,
    rejected,
    latestEvent,
    blockedCodes,
  ] = await Promise.all([
    IntegrationEvent.countDocuments(match),
    IntegrationEvent.countDocuments({
      ...match,
      status: "received",
    }),
    IntegrationEvent.countDocuments({
      ...match,
      status: "processing",
    }),
    IntegrationEvent.countDocuments({
      ...match,
      status: "applied",
    }),
    IntegrationEvent.countDocuments({
      ...match,
      status: "blocked",
    }),
    IntegrationEvent.countDocuments({
      ...match,
      status: "rejected",
    }),
    IntegrationEvent.findOne(match)
      .sort({ createdAt: -1 })
      .lean(),
    IntegrationEvent.aggregate([
      {
        $match: {
          ...match,
          status: {
            $in: ["blocked", "rejected"],
          },
        },
      },
      {
        $group: {
          _id: "$errorCode",
          count: { $sum: 1 },
        },
      },
      {
        $sort: {
          count: -1,
          _id: 1,
        },
      },
      {
        $limit: 20,
      },
    ]),
  ]);

  let state = "never_seen";

  if (!connector.enabled) {
    state = "disabled";
  } else if (blocked > 0 || rejected > 0) {
    state = "needs_attention";
  } else if (processing > 0 || received > 0) {
    state = "processing";
  } else if (connector.lastSuccessfulSyncAt) {
    state = "healthy";
  } else if (connector.lastSeenAt) {
    state = "observed";
  }

  return {
    connector: connectorHealthView(connector),
    state,
    counts: {
      total,
      received,
      processing,
      applied,
      blocked,
      rejected,
    },
    blockedByErrorCode:
      blockedCodes.map((row) => ({
        errorCode: s(row._id) || "UNKNOWN",
        count: row.count,
      })),
    latestEvent:
      latestEvent
        ? eventView(latestEvent)
        : null,
  };
}

async function listIntegrationEvents({
  clinicId,
  connectorId,
  status,
  limit,
}) {
  const connector = await resolveConnectorForClinic({
    clinicId,
    connectorId,
  });

  const filter = {
    clinicId: s(clinicId),
    connectorId: connector._id,
  };

  const normalizedStatus = safeStatus(status);

  if (normalizedStatus) {
    filter.status = normalizedStatus;
  }

  const events = await IntegrationEvent.find(filter)
    .sort({ createdAt: -1 })
    .limit(safeLimit(limit))
    .lean();

  return events.map(eventView);
}

async function getIntegrationEvent({
  clinicId,
  eventId,
}) {
  const id = objectId(
    eventId,
    "eventId"
  );

  const event = await IntegrationEvent.findOne({
    _id: id,
    clinicId: s(clinicId),
  }).lean();

  if (!event) {
    throw codedError(
      "Integration event not found",
      "INTEGRATION_EVENT_NOT_FOUND",
      404
    );
  }

  return eventView(event);
}

async function reprocessIntegrationEvent({
  clinicId,
  eventId,
}) {
  const id = objectId(
    eventId,
    "eventId"
  );

  const event = await IntegrationEvent.findOne({
    _id: id,
    clinicId: s(clinicId),
  });

  if (!event) {
    throw codedError(
      "Integration event not found",
      "INTEGRATION_EVENT_NOT_FOUND",
      404
    );
  }

  if (event.status !== "blocked") {
    throw codedError(
      "Only blocked integration events can be reprocessed",
      "INTEGRATION_EVENT_NOT_BLOCKED",
      409,
      {
        integrationEventId:
          String(event._id),
        status: event.status,
      }
    );
  }

  const result = await processConsumptionEvent({
    connectorId: event.connectorId,
    input: eventInputFromStored(event),
    reprocessBlocked: true,
  });

  await recordConnectorSuccess({
    connectorId: event.connectorId,
  });

  return result;
}

module.exports = {
  recordConnectorSeen,
  recordConnectorSuccess,
  recordConnectorError,
  getConnectorHealth,
  listIntegrationEvents,
  getIntegrationEvent,
  reprocessIntegrationEvent,
};
