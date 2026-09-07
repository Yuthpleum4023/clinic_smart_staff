const mongoose = require("mongoose");

const ConnectorConfigSchema = new mongoose.Schema(
  {
    clinicId: {
      type: String,
      required: true,
      trim: true,
      index: true,
      immutable: true,
    },

    connectorKey: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    externalSystem: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    connectorType: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },

    displayName: {
      type: String,
      default: "",
      trim: true,
    },

    enabled: {
      type: Boolean,
      default: true,
      index: true,
    },

    // Credential lookup identity only.
    // Never store a plaintext connector secret here.
    credentialKeyId: {
      type: String,
      default: "",
      trim: true,
    },

    credentialHash: {
      type: String,
      default: "",
      trim: true,
      select: false,
    },

    credentialVersion: {
      type: Number,
      default: 1,
      min: 1,
    },

    configuration: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },

    lastSeenAt: {
      type: Date,
      default: null,
    },

    lastSuccessfulSyncAt: {
      type: Date,
      default: null,
    },

    lastErrorAt: {
      type: Date,
      default: null,
    },

    lastErrorCode: {
      type: String,
      default: "",
      trim: true,
    },

    createdBy: {
      type: String,
      default: "",
      trim: true,
    },

    updatedBy: {
      type: String,
      default: "",
      trim: true,
    },
  },
  {
    timestamps: true,
  }
);

ConnectorConfigSchema.index(
  {
    clinicId: 1,
    connectorKey: 1,
  },
  {
    unique: true,
  }
);

ConnectorConfigSchema.index(
  {
    credentialKeyId: 1,
  },
  {
    unique: true,
    partialFilterExpression: {
      credentialKeyId: {
        $type: "string",
        $gt: "",
      },
    },
  }
);

ConnectorConfigSchema.index({
  clinicId: 1,
  enabled: 1,
  externalSystem: 1,
});

module.exports = mongoose.model(
  "ConnectorConfig",
  ConnectorConfigSchema
);
