const mongoose = require("mongoose");

const InventoryItemCounterSchema = new mongoose.Schema(
  {
    clinicId: {
      type: String,
      required: true,
      trim: true,
      index: true,
    },
    namespace: {
      type: String,
      required: true,
      trim: true,
      default: "stock_item",
    },
    value: {
      type: Number,
      required: true,
      default: 0,
      min: 0,
    },
  },
  {
    timestamps: true,
  }
);

InventoryItemCounterSchema.index(
  { clinicId: 1, namespace: 1 },
  { unique: true }
);

module.exports = mongoose.model(
  "InventoryItemCounter",
  InventoryItemCounterSchema
);
