const mongoose = require("mongoose");

function s(v) {
  return String(v || "").trim();
}

const ReceiptItemSchema = new mongoose.Schema(
  {
    description: { type: String, required: true, trim: true },
    quantity: { type: Number, default: 1, min: 0 },
    unitPrice: { type: Number, default: 0, min: 0 },
    amount: { type: Number, default: 0, min: 0 },
    note: { type: String, default: "" },
  },
  {
    _id: false,
  }
);

const ClinicSnapshotSchema = new mongoose.Schema(
  {
    clinicName: { type: String, default: "" },
    clinicBranchName: { type: String, default: "" },
    clinicAddress: { type: String, default: "" },
    clinicPhone: { type: String, default: "" },
    clinicTaxId: { type: String, default: "" },
    logoUrl: { type: String, default: "" },
  },
  {
    _id: false,
  }
);

const CustomerSnapshotSchema = new mongoose.Schema(
  {
    customerName: { type: String, required: true, trim: true },
    customerAddress: { type: String, default: "" },
    customerTaxId: { type: String, default: "" },
    customerBranch: { type: String, default: "" },
  },
  {
    _id: false,
  }
);

const PaymentInfoSchema = new mongoose.Schema(
  {
    method: {
      type: String,
      enum: ["cash", "transfer", "cheque", "other"],
      default: "transfer",
    },
    bankName: { type: String, default: "" },
    chequeNo: { type: String, default: "" },
    transferRef: { type: String, default: "" },
    paidAt: { type: Date, default: null },
    note: { type: String, default: "" },
  },
  {
    _id: false,
  }
);

const SocialSecurityReceiptSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, index: true, trim: true },
    receiptNo: { type: String, required: true, unique: true, index: true },

    issueDate: { type: Date, required: true },
    serviceMonth: { type: String, default: "" }, // เช่น 2026-04
    servicePeriodText: { type: String, default: "" }, // เช่น "ประจำเดือนเมษายน 2569"

    status: {
      type: String,
      enum: ["draft", "issued", "void"],
      default: "issued",
      index: true,
    },

    clinicSnapshot: {
      type: ClinicSnapshotSchema,
      required: true,
      default: () => ({}),
    },

    customerSnapshot: {
      type: CustomerSnapshotSchema,
      required: true,
      default: () => ({}),
    },

    items: {
      type: [ReceiptItemSchema],
      default: [],
      validate: {
        validator: Array.isArray,
        message: "items must be an array",
      },
    },

    subtotal: { type: Number, required: true, default: 0, min: 0 },
    withholdingTax: { type: Number, required: true, default: 0, min: 0 },
    netAmount: { type: Number, required: true, default: 0, min: 0 },
    amountInThaiText: { type: String, default: "" },

    paymentInfo: {
      type: PaymentInfoSchema,
      default: () => ({}),
    },

    note: { type: String, default: "" },

    pdfPath: { type: String, default: "" },
    pdfUrl: { type: String, default: "" },
    pdfGeneratedAt: { type: Date, default: null },

    createdByUserId: { type: String, default: "", index: true },
    createdByStaffId: { type: String, default: "" },
    updatedByUserId: { type: String, default: "" },

    voidReason: { type: String, default: "" },
    voidedAt: { type: Date, default: null },
    voidedByUserId: { type: String, default: "" },
  },
  {
    timestamps: true,
  }
);

SocialSecurityReceiptSchema.index({ clinicId: 1, createdAt: -1 });
SocialSecurityReceiptSchema.index({ clinicId: 1, issueDate: -1 });
SocialSecurityReceiptSchema.index({ clinicId: 1, status: 1, issueDate: -1 });
SocialSecurityReceiptSchema.index({ "customerSnapshot.customerName": 1 });

SocialSecurityReceiptSchema.pre("validate", function (next) {
  if (!this.amountInThaiText && Number(this.netAmount || 0) >= 0) {
    this.amountInThaiText = s(this.amountInThaiText);
  }
  next();
});

module.exports =
  mongoose.models.SocialSecurityReceipt ||
  mongoose.model("SocialSecurityReceipt", SocialSecurityReceiptSchema);