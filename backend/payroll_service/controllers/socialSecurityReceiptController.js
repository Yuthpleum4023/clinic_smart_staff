const fs = require("fs");

const SocialSecurityReceipt = require("../models/SocialSecurityReceipt");
const { nextSocialSecurityReceiptNo } = require("../services/receiptRunningService");
const {
  calculateReceiptAmounts,
  round2,
} = require("../utils/receiptAmount");
const { numberToThaiText } = require("../utils/numberToThaiText");
const {
  createPdfFileFromReceipt,
} = require("../services/socialSecurityReceiptPdfService");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function isValidDateInput(v) {
  const d = new Date(v);
  return !Number.isNaN(d.getTime());
}

function toDateOrNow(v) {
  return isValidDateInput(v) ? new Date(v) : new Date();
}

function parseBoolean(v, fallback = false) {
  if (typeof v === "boolean") return v;
  const x = s(v).toLowerCase();
  if (["true", "1", "yes", "y"].includes(x)) return true;
  if (["false", "0", "no", "n"].includes(x)) return false;
  return fallback;
}

function getPrincipal(req) {
  const userId = s(req.user?.userId || req.user?._id || req.userCtx?.userId);
  const staffId = s(req.user?.staffId);
  const role = s(req.user?.role || req.userCtx?.role);
  const clinicId =
    s(req.user?.clinicId) ||
    s(req.userCtx?.clinicId) ||
    s(req.body?.clinicId) ||
    s(req.query?.clinicId) ||
    s(req.params?.clinicId);

  return {
    userId,
    staffId,
    role,
    clinicId,
  };
}

function normalizeItems(items = []) {
  return Array.isArray(items) ? items : [];
}

function sanitizeClinicSnapshot(raw = {}, clinicId = "") {
  return {
    clinicName: s(raw.clinicName),
    clinicBranchName: s(raw.clinicBranchName),
    clinicAddress: s(raw.clinicAddress),
    clinicPhone: s(raw.clinicPhone),
    clinicTaxId: s(raw.clinicTaxId),
    logoUrl: s(raw.logoUrl),
    clinicId: s(clinicId),
  };
}

function sanitizeCustomerSnapshot(raw = {}) {
  return {
    customerName: s(raw.customerName),
    customerAddress: s(raw.customerAddress),
    customerTaxId: s(raw.customerTaxId),
    customerBranch: s(raw.customerBranch),
  };
}

function sanitizePaymentInfo(raw = {}) {
  const method = s(raw.method).toLowerCase();
  return {
    method: ["cash", "transfer", "cheque", "other"].includes(method)
      ? method
      : "transfer",
    bankName: s(raw.bankName),
    chequeNo: s(raw.chequeNo),
    transferRef: s(raw.transferRef),
    paidAt:
      raw.paidAt && isValidDateInput(raw.paidAt) ? new Date(raw.paidAt) : null,
    note: s(raw.note),
  };
}

function formatReceiptResponse(doc) {
  if (!doc) return null;
  const x = typeof doc.toObject === "function" ? doc.toObject() : doc;

  return {
    id: String(x._id || ""),
    receiptNo: s(x.receiptNo),
    clinicId: s(x.clinicId),
    issueDate: x.issueDate || null,
    serviceMonth: s(x.serviceMonth),
    servicePeriodText: s(x.servicePeriodText),
    status: s(x.status),

    clinicSnapshot: {
      clinicName: s(x.clinicSnapshot?.clinicName),
      clinicBranchName: s(x.clinicSnapshot?.clinicBranchName),
      clinicAddress: s(x.clinicSnapshot?.clinicAddress),
      clinicPhone: s(x.clinicSnapshot?.clinicPhone),
      clinicTaxId: s(x.clinicSnapshot?.clinicTaxId),
      logoUrl: s(x.clinicSnapshot?.logoUrl),
    },

    customerSnapshot: {
      customerName: s(x.customerSnapshot?.customerName),
      customerAddress: s(x.customerSnapshot?.customerAddress),
      customerTaxId: s(x.customerSnapshot?.customerTaxId),
      customerBranch: s(x.customerSnapshot?.customerBranch),
    },

    items: Array.isArray(x.items)
      ? x.items.map((item) => ({
          description: s(item.description),
          quantity: round2(n(item.quantity, 1)),
          unitPrice: round2(n(item.unitPrice, 0)),
          amount: round2(n(item.amount, 0)),
          note: s(item.note),
        }))
      : [],

    subtotal: round2(n(x.subtotal, 0)),
    withholdingTax: round2(n(x.withholdingTax, 0)),
    netAmount: round2(n(x.netAmount, 0)),
    amountInThaiText: s(x.amountInThaiText),

    paymentInfo: {
      method: s(x.paymentInfo?.method),
      bankName: s(x.paymentInfo?.bankName),
      chequeNo: s(x.paymentInfo?.chequeNo),
      transferRef: s(x.paymentInfo?.transferRef),
      paidAt: x.paymentInfo?.paidAt || null,
      note: s(x.paymentInfo?.note),
    },

    note: s(x.note),

    pdfPath: s(x.pdfPath),
    pdfUrl: s(x.pdfUrl),
    pdfGeneratedAt: x.pdfGeneratedAt || null,

    createdByUserId: s(x.createdByUserId),
    createdByStaffId: s(x.createdByStaffId),
    updatedByUserId: s(x.updatedByUserId),

    voidReason: s(x.voidReason),
    voidedAt: x.voidedAt || null,
    voidedByUserId: s(x.voidedByUserId),

    createdAt: x.createdAt || null,
    updatedAt: x.updatedAt || null,
  };
}

function buildListQuery(req, clinicId) {
  const q = {
    clinicId,
  };

  const status = s(req.query?.status).toLowerCase();
  if (["draft", "issued", "void"].includes(status)) {
    q.status = status;
  }

  const receiptNo = s(req.query?.receiptNo);
  if (receiptNo) {
    q.receiptNo = { $regex: receiptNo, $options: "i" };
  }

  const customerName = s(req.query?.customerName);
  if (customerName) {
    q["customerSnapshot.customerName"] = {
      $regex: customerName,
      $options: "i",
    };
  }

  const fromDate = s(req.query?.fromDate);
  const toDate = s(req.query?.toDate);
  if (fromDate || toDate) {
    q.issueDate = {};
    if (fromDate && isValidDateInput(fromDate)) {
      q.issueDate.$gte = new Date(fromDate);
    }
    if (toDate && isValidDateInput(toDate)) {
      const d = new Date(toDate);
      d.setHours(23, 59, 59, 999);
      q.issueDate.$lte = d;
    }
    if (!Object.keys(q.issueDate).length) {
      delete q.issueDate;
    }
  }

  return q;
}

async function findReceiptForRequest(req, receiptId, clinicId) {
  const query = { _id: receiptId };
  if (clinicId) {
    query.clinicId = clinicId;
  }
  return SocialSecurityReceipt.findOne(query);
}

async function createReceipt(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(req.body?.clinicId || principal.clinicId);

    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        code: "CLINIC_ID_REQUIRED",
        message: "clinicId is required",
      });
    }

    const clinicSnapshot = sanitizeClinicSnapshot(
      req.body?.clinicSnapshot,
      clinicId
    );
    const customerSnapshot = sanitizeCustomerSnapshot(
      req.body?.customerSnapshot
    );
    const paymentInfo = sanitizePaymentInfo(req.body?.paymentInfo);

    if (!customerSnapshot.customerName) {
      return res.status(400).json({
        ok: false,
        code: "CUSTOMER_NAME_REQUIRED",
        message: "customerSnapshot.customerName is required",
      });
    }

    const amountResult = calculateReceiptAmounts({
      items: normalizeItems(req.body?.items),
      subtotal: req.body?.subtotal,
      withholdingTax: req.body?.withholdingTax,
      withholdingPercent: req.body?.withholdingPercent,
    });

    if (!amountResult.items.length) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ITEMS_REQUIRED",
        message: "At least one receipt item is required",
      });
    }

    const issueDate = toDateOrNow(req.body?.issueDate);
    const receiptNo =
      s(req.body?.receiptNo) ||
      (await nextSocialSecurityReceiptNo({ clinicId, issueDate }));

    const netAmountThaiText = numberToThaiText(amountResult.netAmount);

    const doc = await SocialSecurityReceipt.create({
      clinicId,
      receiptNo,
      issueDate,
      serviceMonth: s(req.body?.serviceMonth),
      servicePeriodText: s(req.body?.servicePeriodText),
      status: ["draft", "issued"].includes(s(req.body?.status))
        ? s(req.body?.status)
        : "issued",

      clinicSnapshot,
      customerSnapshot,
      items: amountResult.items,

      subtotal: amountResult.subtotal,
      withholdingTax: amountResult.withholdingTax,
      netAmount: amountResult.netAmount,
      amountInThaiText: netAmountThaiText,

      paymentInfo,
      note: s(req.body?.note),

      createdByUserId: principal.userId,
      createdByStaffId: principal.staffId,
      updatedByUserId: principal.userId,
    });

    return res.status(201).json({
      ok: true,
      code: "RECEIPT_CREATED",
      message: "Social security receipt created successfully",
      receipt: formatReceiptResponse(doc),
    });
  } catch (err) {
    const msg = s(err?.message);

    if (err?.code === 11000 && msg.includes("receiptNo")) {
      return res.status(409).json({
        ok: false,
        code: "RECEIPT_NO_ALREADY_EXISTS",
        message: "Receipt number already exists",
      });
    }

    return res.status(500).json({
      ok: false,
      code: "CREATE_RECEIPT_FAILED",
      message: msg || "Failed to create social security receipt",
    });
  }
}

async function listReceipts(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(req.query?.clinicId || principal.clinicId);

    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        code: "CLINIC_ID_REQUIRED",
        message: "clinicId is required",
      });
    }

    const page = Math.max(1, parseInt(req.query?.page, 10) || 1);
    const limit = Math.min(
      100,
      Math.max(1, parseInt(req.query?.limit, 10) || 20)
    );
    const skip = (page - 1) * limit;

    const query = buildListQuery(req, clinicId);

    const [rows, total] = await Promise.all([
      SocialSecurityReceipt.find(query)
        .sort({ issueDate: -1, createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      SocialSecurityReceipt.countDocuments(query),
    ]);

    return res.json({
      ok: true,
      code: "RECEIPT_LIST_OK",
      page,
      limit,
      total,
      hasMore: skip + rows.length < total,
      receipts: rows.map(formatReceiptResponse),
    });
  } catch (err) {
    return res.status(500).json({
      ok: false,
      code: "LIST_RECEIPTS_FAILED",
      message: s(err?.message) || "Failed to list social security receipts",
    });
  }
}

async function getReceiptById(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(req.query?.clinicId || principal.clinicId);
    const receiptId = s(req.params?.id);

    if (!receiptId) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ID_REQUIRED",
        message: "Receipt id is required",
      });
    }

    const doc = await findReceiptForRequest(req, receiptId, clinicId);
    if (!doc) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_NOT_FOUND",
        message: "Social security receipt not found",
      });
    }

    return res.json({
      ok: true,
      code: "RECEIPT_DETAIL_OK",
      receipt: formatReceiptResponse(doc),
    });
  } catch (err) {
    return res.status(500).json({
      ok: false,
      code: "GET_RECEIPT_FAILED",
      message: s(err?.message) || "Failed to get social security receipt",
    });
  }
}

async function updateReceipt(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(
      req.body?.clinicId || req.query?.clinicId || principal.clinicId
    );
    const receiptId = s(req.params?.id);

    if (!receiptId) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ID_REQUIRED",
        message: "Receipt id is required",
      });
    }

    const doc = await findReceiptForRequest(req, receiptId, clinicId);
    if (!doc) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_NOT_FOUND",
        message: "Social security receipt not found",
      });
    }

    if (doc.status === "void") {
      return res.status(409).json({
        ok: false,
        code: "RECEIPT_ALREADY_VOID",
        message: "Void receipt cannot be updated",
      });
    }

    if (req.body?.issueDate && isValidDateInput(req.body.issueDate)) {
      doc.issueDate = new Date(req.body.issueDate);
    }

    if ("serviceMonth" in (req.body || {})) {
      doc.serviceMonth = s(req.body.serviceMonth);
    }

    if ("servicePeriodText" in (req.body || {})) {
      doc.servicePeriodText = s(req.body.servicePeriodText);
    }

    if ("status" in (req.body || {})) {
      const status = s(req.body.status);
      if (["draft", "issued"].includes(status)) {
        doc.status = status;
      }
    }

    if (req.body?.clinicSnapshot) {
      doc.clinicSnapshot = {
        ...(typeof doc.clinicSnapshot?.toObject === "function"
          ? doc.clinicSnapshot.toObject()
          : doc.clinicSnapshot || {}),
        ...sanitizeClinicSnapshot(req.body.clinicSnapshot, doc.clinicId),
      };
    }

    if (req.body?.customerSnapshot) {
      const customerSnapshot = sanitizeCustomerSnapshot(
        req.body.customerSnapshot
      );
      if (!customerSnapshot.customerName) {
        return res.status(400).json({
          ok: false,
          code: "CUSTOMER_NAME_REQUIRED",
          message: "customerSnapshot.customerName is required",
        });
      }
      doc.customerSnapshot = {
        ...(typeof doc.customerSnapshot?.toObject === "function"
          ? doc.customerSnapshot.toObject()
          : doc.customerSnapshot || {}),
        ...customerSnapshot,
      };
    }

    if (req.body?.paymentInfo) {
      doc.paymentInfo = {
        ...(typeof doc.paymentInfo?.toObject === "function"
          ? doc.paymentInfo.toObject()
          : doc.paymentInfo || {}),
        ...sanitizePaymentInfo(req.body.paymentInfo),
      };
    }

    const hasAmountRelatedUpdate =
      "items" in (req.body || {}) ||
      "subtotal" in (req.body || {}) ||
      "withholdingTax" in (req.body || {}) ||
      "withholdingPercent" in (req.body || {});

    if (hasAmountRelatedUpdate) {
      const amountResult = calculateReceiptAmounts({
        items:
          "items" in (req.body || {})
            ? normalizeItems(req.body.items)
            : doc.items,
        subtotal:
          "subtotal" in (req.body || {}) ? req.body.subtotal : doc.subtotal,
        withholdingTax:
          "withholdingTax" in (req.body || {})
            ? req.body.withholdingTax
            : doc.withholdingTax,
        withholdingPercent:
          "withholdingPercent" in (req.body || {})
            ? req.body.withholdingPercent
            : undefined,
      });

      if (!amountResult.items.length) {
        return res.status(400).json({
          ok: false,
          code: "RECEIPT_ITEMS_REQUIRED",
          message: "At least one receipt item is required",
        });
      }

      doc.items = amountResult.items;
      doc.subtotal = amountResult.subtotal;
      doc.withholdingTax = amountResult.withholdingTax;
      doc.netAmount = amountResult.netAmount;
      doc.amountInThaiText = numberToThaiText(amountResult.netAmount);
    }

    if ("note" in (req.body || {})) {
      doc.note = s(req.body.note);
    }

    if ("pdfPath" in (req.body || {})) {
      doc.pdfPath = s(req.body.pdfPath);
    }

    if ("pdfUrl" in (req.body || {})) {
      doc.pdfUrl = s(req.body.pdfUrl);
    }

    if (parseBoolean(req.body?.markPdfGenerated, false)) {
      doc.pdfGeneratedAt = new Date();
    }

    doc.updatedByUserId = principal.userId;

    await doc.save();

    return res.json({
      ok: true,
      code: "RECEIPT_UPDATED",
      message: "Social security receipt updated successfully",
      receipt: formatReceiptResponse(doc),
    });
  } catch (err) {
    return res.status(500).json({
      ok: false,
      code: "UPDATE_RECEIPT_FAILED",
      message: s(err?.message) || "Failed to update social security receipt",
    });
  }
}

async function voidReceipt(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(
      req.body?.clinicId || req.query?.clinicId || principal.clinicId
    );
    const receiptId = s(req.params?.id);
    const voidReason = s(req.body?.voidReason || req.body?.reason);

    if (!receiptId) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ID_REQUIRED",
        message: "Receipt id is required",
      });
    }

    const doc = await findReceiptForRequest(req, receiptId, clinicId);
    if (!doc) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_NOT_FOUND",
        message: "Social security receipt not found",
      });
    }

    if (doc.status === "void") {
      return res.status(409).json({
        ok: false,
        code: "RECEIPT_ALREADY_VOID",
        message: "This receipt is already void",
      });
    }

    doc.status = "void";
    doc.voidReason = voidReason;
    doc.voidedAt = new Date();
    doc.voidedByUserId = principal.userId;
    doc.updatedByUserId = principal.userId;

    await doc.save();

    return res.json({
      ok: true,
      code: "RECEIPT_VOIDED",
      message: "Social security receipt voided successfully",
      receipt: formatReceiptResponse(doc),
    });
  } catch (err) {
    return res.status(500).json({
      ok: false,
      code: "VOID_RECEIPT_FAILED",
      message: s(err?.message) || "Failed to void social security receipt",
    });
  }
}

async function generateReceiptPdf(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(
      req.body?.clinicId || req.query?.clinicId || principal.clinicId
    );
    const receiptId = s(req.params?.id);

    if (!receiptId) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ID_REQUIRED",
        message: "Receipt id is required",
      });
    }

    const doc = await findReceiptForRequest(req, receiptId, clinicId);
    if (!doc) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_NOT_FOUND",
        message: "Social security receipt not found",
      });
    }

    if (doc.status === "void") {
      return res.status(409).json({
        ok: false,
        code: "RECEIPT_ALREADY_VOID",
        message: "Void receipt cannot generate PDF",
      });
    }

    const result = await createPdfFileFromReceipt(doc, {
      logoUrl: s(req.body?.logoUrl) || s(doc.clinicSnapshot?.logoUrl),
    });

    doc.pdfPath = s(result.pdfPath);
    doc.pdfUrl = s(result.pdfUrl);
    doc.pdfGeneratedAt = new Date();
    doc.updatedByUserId = principal.userId;

    await doc.save();

    return res.json({
      ok: true,
      code: "RECEIPT_PDF_GENERATED",
      message: "Social security receipt PDF generated successfully",
      receipt: formatReceiptResponse(doc),
      pdf: {
        fileName: s(result.pdfFileName),
        pdfPath: s(result.pdfPath),
        pdfUrl: s(result.pdfUrl),
      },
    });
  } catch (err) {
    return res.status(500).json({
      ok: false,
      code: "GENERATE_RECEIPT_PDF_FAILED",
      message: s(err?.message) || "Failed to generate receipt PDF",
    });
  }
}

async function getReceiptPdfInfo(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(req.query?.clinicId || principal.clinicId);
    const receiptId = s(req.params?.id);

    if (!receiptId) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ID_REQUIRED",
        message: "Receipt id is required",
      });
    }

    const doc = await findReceiptForRequest(req, receiptId, clinicId);
    if (!doc) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_NOT_FOUND",
        message: "Social security receipt not found",
      });
    }

    if (!s(doc.pdfPath)) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_PDF_NOT_FOUND",
        message: "Receipt PDF has not been generated yet",
      });
    }

    return res.json({
      ok: true,
      code: "RECEIPT_PDF_INFO_OK",
      pdf: {
        pdfPath: s(doc.pdfPath),
        pdfUrl: s(doc.pdfUrl),
        pdfGeneratedAt: doc.pdfGeneratedAt || null,
      },
      receipt: formatReceiptResponse(doc),
    });
  } catch (err) {
    return res.status(500).json({
      ok: false,
      code: "GET_RECEIPT_PDF_INFO_FAILED",
      message: s(err?.message) || "Failed to get receipt PDF info",
    });
  }
}

async function streamReceiptPdf(req, res) {
  try {
    const principal = getPrincipal(req);
    const clinicId = s(req.query?.clinicId || principal.clinicId);
    const receiptId = s(req.params?.id);

    if (!receiptId) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ID_REQUIRED",
        message: "Receipt id is required",
      });
    }

    const doc = await findReceiptForRequest(req, receiptId, clinicId);
    if (!doc) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_NOT_FOUND",
        message: "Social security receipt not found",
      });
    }

    const pdfPath = s(doc.pdfPath);
    if (!pdfPath || !fs.existsSync(pdfPath)) {
      return res.status(404).json({
        ok: false,
        code: "RECEIPT_PDF_FILE_NOT_FOUND",
        message: "Receipt PDF file not found",
      });
    }

    const download = parseBoolean(req.query?.download, false);
    const fileName = `${s(doc.receiptNo || "receipt")}.pdf`.replace(
      /[\\/:*?"<>|]+/g,
      "_"
    );

    res.setHeader("Content-Type", "application/pdf");
    res.setHeader(
      "Content-Disposition",
      `${download ? "attachment" : "inline"}; filename="${fileName}"`
    );

    return fs.createReadStream(pdfPath).pipe(res);
  } catch (err) {
    return res.status(500).json({
      ok: false,
      code: "STREAM_RECEIPT_PDF_FAILED",
      message: s(err?.message) || "Failed to open receipt PDF",
    });
  }
}

module.exports = {
  createReceipt,
  listReceipts,
  getReceiptById,
  updateReceipt,
  voidReceipt,
  generateReceiptPdf,
  getReceiptPdfInfo,
  streamReceiptPdf,
  formatReceiptResponse,
};