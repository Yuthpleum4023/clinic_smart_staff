const mongoose = require("mongoose");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

const ReceiptItemSchema = new mongoose.Schema(
  {
    description: { type: String, required: true, trim: true },
    quantity: { type: Number, default: 1, min: 0 },
    unitPrice: { type: Number, default: 0, min: 0 },
    amount: { type: Number, default: 0, min: 0 },

    // ✅ NEW
    withholdingTaxAmount: { type: Number, default: 0, min: 0 },
    netAmount: { type: Number, default: 0, min: 0 },

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

    // ✅ NEW
    withholderTaxId: { type: String, default: "" },
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

    // ✅ NEW
    accountName: { type: String, default: "" },
    accountNumber: { type: String, default: "" },

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

    withholdingTaxEnabled: { type: Boolean, default: false },

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
  this.subtotal = Math.max(0, n(this.subtotal, 0));
  this.withholdingTax = Math.max(0, n(this.withholdingTax, 0));

  if (!Array.isArray(this.items)) {
    this.items = [];
  }

  let computedSubtotal = 0;
  let computedWithholdingTax = 0;

  this.items = this.items.map((item) => {
    const quantity = Math.max(0, n(item?.quantity, 0));
    const unitPrice = Math.max(0, n(item?.unitPrice, 0));
    const rawAmount = n(item?.amount, quantity * unitPrice);
    const amount = Math.max(0, rawAmount);
    const withholdingTaxAmount = Math.max(
      0,
      Math.min(amount, n(item?.withholdingTaxAmount, 0))
    );
    const netAmount = Math.max(0, amount - withholdingTaxAmount);

    computedSubtotal += amount;
    computedWithholdingTax += withholdingTaxAmount;

    return {
      ...item,
      description: s(item?.description),
      quantity,
      unitPrice,
      amount,
      withholdingTaxAmount,
      netAmount,
      note: s(item?.note),
    };
  });

  this.subtotal = computedSubtotal;

  if (!this.withholdingTaxEnabled) {
    this.withholdingTax = 0;
    this.items = this.items.map((item) => ({
      ...item,
      withholdingTaxAmount: 0,
      netAmount: Math.max(0, n(item?.amount, 0)),
    }));
  } else {
    this.withholdingTax = computedWithholdingTax;
  }

  this.netAmount = Math.max(0, this.subtotal - this.withholdingTax);

  this.note = s(this.note);

  if (this.clinicSnapshot) {
    this.clinicSnapshot.clinicName = s(this.clinicSnapshot.clinicName);
    this.clinicSnapshot.clinicBranchName = s(this.clinicSnapshot.clinicBranchName);
    this.clinicSnapshot.clinicAddress = s(this.clinicSnapshot.clinicAddress);
    this.clinicSnapshot.clinicPhone = s(this.clinicSnapshot.clinicPhone);
    this.clinicSnapshot.clinicTaxId = s(this.clinicSnapshot.clinicTaxId);
    this.clinicSnapshot.logoUrl = s(this.clinicSnapshot.logoUrl);
    this.clinicSnapshot.withholderTaxId = s(
      this.clinicSnapshot.withholderTaxId
    );
  }

  if (this.paymentInfo) {
    this.paymentInfo.method = s(this.paymentInfo.method) || "transfer";
    this.paymentInfo.bankName = s(this.paymentInfo.bankName);
    this.paymentInfo.accountName = s(this.paymentInfo.accountName);
    this.paymentInfo.accountNumber = s(this.paymentInfo.accountNumber);
    this.paymentInfo.chequeNo = s(this.paymentInfo.chequeNo);
    this.paymentInfo.transferRef = s(this.paymentInfo.transferRef);
    this.paymentInfo.note = s(this.paymentInfo.note);

    const allowedMethods = new Set(["cash", "transfer", "cheque", "other"]);
    if (!allowedMethods.has(this.paymentInfo.method)) {
      this.paymentInfo.method = "transfer";
    }
  }

  if (!this.amountInThaiText && Number(this.netAmount || 0) >= 0) {
    this.amountInThaiText = s(this.amountInThaiText);
  }

  next();
});

module.exports =
  mongoose.models.SocialSecurityReceipt ||
  mongoose.model("SocialSecurityReceipt", SocialSecurityReceiptSchema);