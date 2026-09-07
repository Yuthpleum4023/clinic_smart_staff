const mongoose = require("mongoose");

function positiveSafeInteger(value) {
  return (
    Number.isSafeInteger(value) &&
    value > 0
  );
}

const InventoryItemMappingSchema = new mongoose.Schema(
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

    stockItemId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "StockItem",
      required: true,
      index: true,
    },

    // Snapshot/contract of the StockItem unit expected by this mapping.
    // Runtime processing must fail closed if StockItem.unit later differs.
    inventoryUnit: {
      type: String,
      required: true,
      trim: true,
    },

    // normalizedQuantity =
    // externalQuantity * numerator / denominator
    conversionNumerator: {
      type: Number,
      required: true,
      default: 1,
      validate: {
        validator: positiveSafeInteger,
        message:
          "conversionNumerator must be a positive safe integer",
      },
    },

    conversionDenominator: {
      type: Number,
      required: true,
      default: 1,
      validate: {
        validator: positiveSafeInteger,
        message:
          "conversionDenominator must be a positive safe integer",
      },
    },

    active: {
      type: Boolean,
      default: true,
      index: true,
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

InventoryItemMappingSchema.index(
  {
    clinicId: 1,
    connectorId: 1,
    externalItemId: 1,
    externalUnit: 1,
  },
  {
    unique: true,
  }
);

InventoryItemMappingSchema.index({
  clinicId: 1,
  stockItemId: 1,
  active: 1,
});

module.exports = mongoose.model(
  "InventoryItemMapping",
  InventoryItemMappingSchema
);
