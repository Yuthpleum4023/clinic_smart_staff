const mongoose = require("mongoose");

const ReceiptCounterSchema = new mongoose.Schema(
  {
    key: { type: String, required: true, unique: true, index: true },
    seq: { type: Number, default: 0 },
  },
  {
    timestamps: true,
    versionKey: false,
  }
);

module.exports =
  mongoose.models.ReceiptCounter ||
  mongoose.model("ReceiptCounter", ReceiptCounterSchema);