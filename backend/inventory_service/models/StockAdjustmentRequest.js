const mongoose = require("mongoose");

const StockAdjustmentRequestSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, trim: true, index: true },
    stockItemId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "StockItem",
      required: true,
      index: true,
    },

    status: {
      type: String,
      enum: ["pending", "approved", "rejected"],
      default: "pending",
      index: true,
    },

    snapshotQty: { type: Number, required: true },
    observedQty: { type: Number, required: true },
    requestedDelta: { type: Number, required: true },

    reason: { type: String, required: true, trim: true },

    requestedBy: { type: String, required: true, trim: true },
    requestedByStaffId: { type: String, default: "", trim: true },
    requestedByName: { type: String, default: "", trim: true },

    reviewedBy: { type: String, default: "", trim: true },
    reviewedByName: { type: String, default: "", trim: true },
    reviewedAt: { type: Date, default: null },
    resolutionNote: { type: String, default: "", trim: true },

    movementId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "StockMovement",
      default: null,
    },
  },
  { timestamps: true }
);

StockAdjustmentRequestSchema.index({
  clinicId: 1,
  status: 1,
  createdAt: -1,
});

StockAdjustmentRequestSchema.index({
  clinicId: 1,
  stockItemId: 1,
  createdAt: -1,
});

module.exports = mongoose.model(
  "StockAdjustmentRequest",
  StockAdjustmentRequestSchema
);
