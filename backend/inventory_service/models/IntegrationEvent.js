const mongoose = require("mongoose");

const EVENT_STATUSES = [
  "received",
  "applied",
  "blocked",
  "rejected",
];

const IntegrationEventSchema = new mongoose.Schema(
  {
    clinicId: {
      type: String,
      required: true,
      trim: true,
      index: true,
      immutable: true,
    },

    connectorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "ConnectorConfig",
      required: true,
      index: true,
      immutable: true,
    },

    externalSystem: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    externalEventId: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    externalLineId: {
      type: String,
      required: true,
      trim: true,
      default: "0",
      immutable: true,
    },

    payloadHash: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    externalItemId: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    externalUnit: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    externalQuantity: {
      type: Number,
      required: true,
      immutable: true,
    },

    eventType: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    occurredAt: {
      type: Date,
      required: true,
      immutable: true,
    },

    referenceType: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },

    referenceNo: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },

    sourceMetadata: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
      immutable: true,
    },

    status: {
      type: String,
      required: true,
      enum: EVENT_STATUSES,
      default: "received",
      index: true,
    },

    processingAttempts: {
      type: Number,
      required: true,
      default: 0,
      min: 0,
    },

    lastAttemptAt: {
      type: Date,
      default: null,
    },

    mappingId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "InventoryItemMapping",
      default: null,
    },

    stockItemId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "StockItem",
      default: null,
    },

    normalizedQuantity: {
      type: Number,
      default: null,
    },

    stockMovementId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "StockMovement",
      default: null,
    },

    errorCode: {
      type: String,
      default: "",
      trim: true,
    },

    errorMessage: {
      type: String,
      default: "",
      trim: true,
    },

    appliedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

IntegrationEventSchema.index(
  {
    clinicId: 1,
    connectorId: 1,
    externalEventId: 1,
    externalLineId: 1,
  },
  {
    unique: true,
  }
);

IntegrationEventSchema.index({
  clinicId: 1,
  connectorId: 1,
  status: 1,
  createdAt: -1,
});

IntegrationEventSchema.index({
  clinicId: 1,
  status: 1,
  createdAt: -1,
});

IntegrationEventSchema.index(
  {
    stockMovementId: 1,
  },
  {
    partialFilterExpression: {
      stockMovementId: {
        $type: "objectId",
      },
    },
  }
);

module.exports = mongoose.model(
  "IntegrationEvent",
  IntegrationEventSchema
);

module.exports.EVENT_STATUSES = EVENT_STATUSES;
