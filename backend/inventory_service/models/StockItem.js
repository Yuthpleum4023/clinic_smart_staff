const mongoose = require("mongoose");

const StockItemSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, trim: true, index: true },
    name: { type: String, required: true, trim: true },
    sku: { type: String, default: "", trim: true },
    category: { type: String, default: "", trim: true },
    unit: { type: String, required: true, trim: true },

    currentQty: { type: Number, required: true, default: 0 },

    minimumQty: { type: Number, required: true, default: 0, min: 0 },
    lowStockAlertEnabled: { type: Boolean, default: true },
    lowStockActive: { type: Boolean, default: true, index: true },
    lowStockSince: { type: Date, default: null },

    active: { type: Boolean, default: true, index: true },

    createdBy: { type: String, default: "", trim: true },
    updatedBy: { type: String, default: "", trim: true },
  },
  {
    timestamps: true,
    optimisticConcurrency: true,
  }
);

StockItemSchema.index({ clinicId: 1, name: 1 });
StockItemSchema.index({ clinicId: 1, active: 1, name: 1 });
StockItemSchema.index({ clinicId: 1, lowStockActive: 1, active: 1 });
StockItemSchema.index(
  { clinicId: 1, sku: 1 },
  {
    unique: true,
    partialFilterExpression: {
      sku: { $type: "string", $ne: "" },
    },
  }
);

module.exports = mongoose.model("StockItem", StockItemSchema);
