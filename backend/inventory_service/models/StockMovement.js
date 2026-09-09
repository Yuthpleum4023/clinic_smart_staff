const mongoose = require("mongoose");

const MOVEMENT_TYPES = [
  "stock_in",
  "manual_consumption",
  "external_consumption",
  "external_stock_in",
  "adjustment",
  "reversal",
];

const SOURCE_TYPES = [
  "app",
  "connector",
  "adjustment_request",
  "reversal",
  "system",
];

const ItemSnapshotSchema = new mongoose.Schema(
  {
    name: { type: String, default: "", trim: true },
    sku: { type: String, default: "", trim: true },
    category: { type: String, default: "", trim: true },
    unit: { type: String, default: "", trim: true },
  },
  { _id: false }
);

const StockMovementSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, trim: true, index: true },
    stockItemId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "StockItem",
      required: true,
      index: true,
    },

    itemSnapshot: {
      type: ItemSnapshotSchema,
      default: () => ({}),
      immutable: true,
    },

    type: {
      type: String,
      required: true,
      enum: MOVEMENT_TYPES,
      immutable: true,
    },

    quantityDelta: { type: Number, required: true, immutable: true },
    balanceBefore: { type: Number, required: true, immutable: true },
    balanceAfter: { type: Number, required: true, immutable: true },

    sourceType: {
      type: String,
      required: true,
      enum: SOURCE_TYPES,
      immutable: true,
    },
    sourceId: { type: String, default: "", trim: true, immutable: true },
    idempotencyKey: {
      type: String,
      default: "",
      trim: true,
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

    lotNo: { type: String, default: "", trim: true, immutable: true },
    expiryDate: { type: Date, default: null, immutable: true },
    supplier: { type: String, default: "", trim: true, immutable: true },
    invoiceNo: { type: String, default: "", trim: true, immutable: true },

    unitCost: { type: Number, default: null, immutable: true },
    currency: {
      type: String,
      default: "THB",
      trim: true,
      immutable: true,
    },

    performedBy: {
      type: String,
      required: true,
      trim: true,
      immutable: true,
    },
    performedByStaffId: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },
    performedByName: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },
    actorRole: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },

    requestedBy: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },
    requestedByStaffId: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },
    requestedByName: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },

    approvedBy: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },
    approvedByName: {
      type: String,
      default: "",
      trim: true,
      immutable: true,
    },
    approvedAt: { type: Date, default: null, immutable: true },

    reason: { type: String, default: "", trim: true, immutable: true },
    note: { type: String, default: "", trim: true, immutable: true },

    occurredAt: { type: Date, default: Date.now, immutable: true },

    metadata: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
      immutable: true,
    },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
  }
);

StockMovementSchema.index({
  clinicId: 1,
  stockItemId: 1,
  createdAt: -1,
  _id: -1,
});

StockMovementSchema.index({
  clinicId: 1,
  stockItemId: 1,
  occurredAt: -1,
});

StockMovementSchema.index({
  clinicId: 1,
  createdAt: -1,
});

StockMovementSchema.index(
  { clinicId: 1, idempotencyKey: 1 },
  {
    unique: true,
    partialFilterExpression: {
      idempotencyKey: { $type: "string", $ne: "" },
    },
  }
);

function immutableError(next) {
  const err = new Error("StockMovement is immutable");
  err.code = "STOCK_MOVEMENT_IMMUTABLE";
  return next(err);
}

StockMovementSchema.pre("save", function (next) {
  if (!this.isNew) return immutableError(next);
  return next();
});

for (const hook of [
  "updateOne",
  "updateMany",
  "findOneAndUpdate",
  "deleteOne",
  "deleteMany",
  "findOneAndDelete",
]) {
  StockMovementSchema.pre(hook, function (next) {
    return immutableError(next);
  });
}

module.exports = mongoose.model("StockMovement", StockMovementSchema);
module.exports.MOVEMENT_TYPES = MOVEMENT_TYPES;
