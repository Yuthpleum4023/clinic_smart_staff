const mongoose = require("mongoose");

const TaxYTDSchema = new mongoose.Schema(
  {
    employeeId: { type: String, required: true, index: true },
    taxYear: { type: Number, required: true, index: true },

    incomeYTD: { type: Number, default: 0 },
    ssoYTD: { type: Number, default: 0 },
    pvdYTD: { type: Number, default: 0 },

    taxableYTD: { type: Number, default: 0 },
    taxDueYTD: { type: Number, default: 0 },
    taxPaidYTD: { type: Number, default: 0 },
  },
  { timestamps: true }
);

TaxYTDSchema.index({ employeeId: 1, taxYear: 1 }, { unique: true });

module.exports = mongoose.model("TaxYTD", TaxYTDSchema);
