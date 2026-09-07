const crypto = require("crypto");
const mongoose = require("mongoose");

const ConnectorConfig = require("../models/ConnectorConfig");
const IntegrationEvent = require("../models/IntegrationEvent");
const StockItem = require("../models/StockItem");
const StockMovement = require("../models/StockMovement");

const {
  normalizeConsumptionEvent,
} = require("./integrationEventContract");

const {
  convertMappedQuantity,
  resolveMappedInventoryItem,
} = require("./itemMappingService");

const {
  applyMovement,
} = require("./stockLedgerService");

const {
  s,
} = require("../utils/strings");

const BLOCKED_CODES = new Set([
  "ITEM_MAPPING_NOT_FOUND",
  "MAPPED_STOCK_ITEM_NOT_FOUND",
  "STOCK_ITEM_INACTIVE",
  "MAPPING_EXTERNAL_UNIT_MISMATCH",
  "MAPPING_INVENTORY_UNIT_MISMATCH",
  "INVALID_CONVERSION_FACTOR",
  "INVALID_QUANTITY",
  "INSUFFICIENT_STOCK",
  "STOCK_ITEM_NOT_FOUND",
]);

function codedError(
  message,
  code,
  status = 409,
  details = null
) {
  const err = new Error(message);
  err.status = status;
  err.code = code;

  if (details) {
    err.details = details;
  }

  return err;
}

function validConnectorId(value) {
  if (
    !mongoose.Types.ObjectId.isValid(
      String(value || "")
    )
  ) {
    throw codedError(
      "Invalid connectorId",
      "INVALID_CONNECTOR_ID",
      400
    );
  }
}

async function resolveConnector(
  connectorId
) {
  validConnectorId(connectorId);

  const connector =
    await ConnectorConfig.findOne({
      _id: connectorId,
      enabled: true,
    });

  if (!connector) {
    throw codedError(
      "Connector not found or disabled",
      "CONNECTOR_NOT_AVAILABLE",
      403
    );
  }

  if (
    !s(connector.clinicId) ||
    !s(connector.externalSystem)
  ) {
    throw codedError(
      "Connector scope is incomplete",
      "CONNECTOR_SCOPE_INVALID",
      500
    );
  }

  return connector;
}

function eventIdentityFilter(
  connector,
  normalized
) {
  return {
    clinicId: s(connector.clinicId),
    connectorId: connector._id,
    externalEventId:
      normalized.externalEventId,
    externalLineId:
      normalized.externalLineId,
  };
}

function materializationKey(
  connector,
  normalized
) {
  const identity = JSON.stringify([
    "inventory-external-consumption-v1",
    s(connector.clinicId),
    String(connector._id),
    normalized.externalEventId,
    normalized.externalLineId,
  ]);

  const digest = crypto
    .createHash("sha256")
    .update(identity)
    .digest("hex");

  return `integration:v1:${digest}`;
}

function eventDocumentInput(
  connector,
  normalized
) {
  return {
    ...eventIdentityFilter(
      connector,
      normalized
    ),

    externalSystem:
      s(connector.externalSystem),

    payloadHash:
      normalized.payloadHash,

    externalItemId:
      normalized.externalItemId,

    externalUnit:
      normalized.externalUnit,

    externalQuantity:
      normalized.externalQuantity,

    eventType:
      normalized.eventType,

    occurredAt:
      normalized.occurredAt,

    referenceType:
      normalized.referenceType,

    referenceNo:
      normalized.referenceNo,

    sourceMetadata:
      normalized.metadata || {},

    status: "received",
  };
}

async function createOrLoadEvent(
  connector,
  normalized
) {
  const filter =
    eventIdentityFilter(
      connector,
      normalized
    );

  try {
    const event =
      await IntegrationEvent.create(
        eventDocumentInput(
          connector,
          normalized
        )
      );

    return {
      event,
      created: true,
    };
  } catch (err) {
    if (err?.code !== 11000) {
      throw err;
    }

    const existing =
      await IntegrationEvent.findOne(
        filter
      );

    if (!existing) {
      throw err;
    }

    if (
      existing.payloadHash !==
      normalized.payloadHash
    ) {
      throw codedError(
        "External event identity was reused with a different payload",
        "EXTERNAL_EVENT_CONFLICT",
        409,
        {
          integrationEventId:
            String(existing._id),
        }
      );
    }

    return {
      event: existing,
      created: false,
    };
  }
}

async function replayResult(
  event
) {
  const movement =
    event.stockMovementId
      ? await StockMovement.findById(
          event.stockMovementId
        )
      : null;

  const item =
    movement?.stockItemId
      ? await StockItem.findOne({
          _id: movement.stockItemId,
          clinicId: event.clinicId,
        })
      : null;

  return {
    integrationEvent: event,
    movement,
    item,
    idempotentReplay: true,
    lowStockTransition: "none",
  };
}

function throwStoredBlock(event) {
  throw codedError(
    event.errorMessage ||
      "Integration event is blocked",
    event.errorCode ||
      "INTEGRATION_EVENT_BLOCKED",
    409,
    {
      integrationEventId:
        String(event._id),
    }
  );
}

async function markBlocked(
  event,
  err
) {
  const now = new Date();

  const updated =
    await IntegrationEvent.findOneAndUpdate(
      {
        _id: event._id,
        payloadHash: event.payloadHash,
        status: {
          $in: [
            "received",
            "blocked",
          ],
        },
      },
      {
        $set: {
          status: "blocked",
          lastAttemptAt: now,
          errorCode:
            s(err?.code) ||
            "INTEGRATION_PROCESSING_BLOCKED",
          errorMessage:
            s(err?.message) ||
            "Integration processing blocked",
        },
        $inc: {
          processingAttempts: 1,
        },
      },
      {
        new: true,
      }
    );

  return (
    updated ||
    IntegrationEvent.findById(
      event._id
    )
  );
}

async function processReceivedEvent({
  event,
  connector,
  normalized,
  reprocessBlocked = false,
}) {
  const session =
    await mongoose.startSession();

  let result = null;

  try {
    await session.withTransaction(
      async () => {
        const claimed =
          await IntegrationEvent.findOneAndUpdate(
            {
              _id: event._id,
              payloadHash:
                normalized.payloadHash,
              status:
                reprocessBlocked
                  ? {
                      $in: [
                        "received",
                        "blocked",
                      ],
                    }
                  : "received",
            },
            {
              $set: {
                status: "processing",
                lastAttemptAt:
                  new Date(),
                errorCode: "",
                errorMessage: "",
              },
              $inc: {
                processingAttempts: 1,
              },
            },
            {
              new: true,
              session,
            }
          );

        if (!claimed) {
          return;
        }

        const {
          mapping,
          item,
        } =
          await resolveMappedInventoryItem({
            clinicId:
              connector.clinicId,
            connectorId:
              connector._id,
            externalItemId:
              normalized.externalItemId,
            externalUnit:
              normalized.externalUnit,
            session,
          });

        const normalizedQuantity =
          convertMappedQuantity({
            externalQuantity:
              normalized.externalQuantity,
            conversionNumerator:
              mapping.conversionNumerator,
            conversionDenominator:
              mapping.conversionDenominator,
          });

        const movementResult =
          await applyMovement(
            {
              clinicId:
                connector.clinicId,

              stockItemId:
                item._id,

              type:
                "external_consumption",

              quantityDelta:
                -normalizedQuantity,

              sourceType:
                "connector",

              sourceId:
                String(connector._id),

              idempotencyKey:
                materializationKey(
                  connector,
                  normalized
                ),

              referenceType:
                normalized.referenceType ||
                normalized.eventType,

              referenceNo:
                normalized.referenceNo,

              performedBy:
                `connector:${connector._id}`,

              performedByName:
                s(connector.displayName) ||
                s(connector.connectorKey) ||
                s(connector.externalSystem),

              actorRole:
                "connector",

              reason:
                "external consumption",

              occurredAt:
                normalized.occurredAt,

              metadata: {
                integrationEventId:
                  String(claimed._id),
                connectorId:
                  String(connector._id),
                externalSystem:
                  s(connector.externalSystem),
                externalEventId:
                  normalized.externalEventId,
                externalLineId:
                  normalized.externalLineId,
                externalItemId:
                  normalized.externalItemId,
                externalUnit:
                  normalized.externalUnit,
                mappingId:
                  String(mapping._id),
              },
            },
            {
              session,
            }
          );

        claimed.status = "applied";
        claimed.mappingId =
          mapping._id;
        claimed.stockItemId =
          item._id;
        claimed.normalizedQuantity =
          normalizedQuantity;
        claimed.stockMovementId =
          movementResult.movement._id;
        claimed.errorCode = "";
        claimed.errorMessage = "";
        claimed.appliedAt =
          new Date();

        await claimed.save({
          session,
        });

        result = {
          integrationEvent:
            claimed,
          movement:
            movementResult.movement,
          item:
            movementResult.item,
          idempotentReplay:
            !!movementResult.idempotentReplay,
          lowStockTransition:
            movementResult.lowStockTransition ||
            "none",
        };
      }
    );

    if (result) {
      return result;
    }

    const finalEvent =
      await IntegrationEvent.findById(
        event._id
      );

    if (
      finalEvent?.payloadHash !==
      normalized.payloadHash
    ) {
      throw codedError(
        "Integration event payload changed during processing",
        "EXTERNAL_EVENT_CONFLICT"
      );
    }

    if (
      finalEvent?.status ===
      "applied"
    ) {
      return replayResult(
        finalEvent
      );
    }

    if (
      finalEvent?.status ===
        "blocked" ||
      finalEvent?.status ===
        "rejected"
    ) {
      return throwStoredBlock(
        finalEvent
      );
    }

    throw codedError(
      "Integration event could not be claimed for processing",
      "INTEGRATION_EVENT_NOT_CLAIMED",
      409,
      {
        integrationEventId:
          String(event._id),
        status:
          finalEvent?.status || "",
      }
    );
  } catch (err) {
    const finalEvent =
      await IntegrationEvent.findById(
        event._id
      );

    if (
      finalEvent &&
      finalEvent.payloadHash ===
        normalized.payloadHash &&
      finalEvent.status ===
        "applied"
    ) {
      return replayResult(
        finalEvent
      );
    }

    if (
      BLOCKED_CODES.has(
        s(err?.code)
      )
    ) {
      const blocked =
        await markBlocked(
          event,
          err
        );

      if (
        blocked?.status ===
        "applied"
      ) {
        return replayResult(
          blocked
        );
      }

      err.details = {
        ...(err.details || {}),
        integrationEventId:
          String(event._id),
      };
    }

    throw err;
  } finally {
    await session.endSession();
  }
}

async function processConsumptionEvent({
  connectorId,
  input,
  reprocessBlocked = false,
}) {
  const normalized =
    normalizeConsumptionEvent(
      input || {}
    );

  const connector =
    await resolveConnector(
      connectorId
    );

  const {
    event,
    created,
  } =
    await createOrLoadEvent(
      connector,
      normalized
    );

  if (!created) {
    if (event.status === "applied") {
      return replayResult(event);
    }

    if (
      event.status === "rejected"
    ) {
      return throwStoredBlock(
        event
      );
    }

    if (
      event.status === "blocked" &&
      !reprocessBlocked
    ) {
      return throwStoredBlock(
        event
      );
    }
  }

  return processReceivedEvent({
    event,
    connector,
    normalized,
    reprocessBlocked:
      !!reprocessBlocked,
  });
}

module.exports = {
  processConsumptionEvent,
  materializationKey,
};
