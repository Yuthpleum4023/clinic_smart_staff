const fs = require("fs");

const Clinic = require("../models/Clinic");
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

function escapeRegex(v) {
  return s(v).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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
    withholderTaxId: s(raw.withholderTaxId),
    clinicId: s(clinicId),
  };
}

function buildClinicSnapshotFromClinic(clinic = {}, clinicId = "") {
  return {
    clinicName: s(clinic.name),
    clinicBranchName: s(clinic.branchName),
    clinicAddress: s(clinic.address),
    clinicPhone: s(clinic.phone),
    clinicTaxId: s(clinic.taxId),
    logoUrl: s(clinic.logoUrl),
    withholderTaxId: s(clinic.withholderTaxId),
    clinicId: s(clinicId || clinic.clinicId),
  };
}

async function resolveMergedClinicSnapshot({
  clinicId,
  inputSnapshot,
}) {
  const rawInput =
    inputSnapshot && typeof inputSnapshot === "object" ? inputSnapshot : {};

  const clinic = clinicId
    ? await Clinic.findOne({ clinicId }).lean()
    : null;

  const fromClinic = buildClinicSnapshotFromClinic(clinic || {}, clinicId);
  const fromInput = sanitizeClinicSnapshot(rawInput, clinicId);

  return {
    clinicName: s(fromInput.clinicName || fromClinic.clinicName),
    clinicBranchName: s(
      fromInput.clinicBranchName || fromClinic.clinicBranchName
    ),
    clinicAddress: s(fromInput.clinicAddress || fromClinic.clinicAddress),
    clinicPhone: s(fromInput.clinicPhone || fromClinic.clinicPhone),
    clinicTaxId: s(fromInput.clinicTaxId || fromClinic.clinicTaxId),
    logoUrl: s(fromInput.logoUrl || fromClinic.logoUrl),
    withholderTaxId: s(
      fromInput.withholderTaxId || fromClinic.withholderTaxId
    ),
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

function normalizePaymentMethod(method) {
  const x = s(method).toLowerCase();
  if (x === "check") return "cheque";
  return ["cash", "transfer", "cheque", "other"].includes(x)
    ? x
    : "transfer";
}

function sanitizePaymentInfo(raw = {}, body = {}) {
  const method =
    raw.method != null ? raw.method : body.paymentMethod;

  return {
    method: normalizePaymentMethod(method),
    bankName: s(raw.bankName || body.bankName),
    accountName: s(raw.accountName || body.accountName),
    accountNumber: s(raw.accountNumber || body.accountNumber),
    chequeNo: s(raw.chequeNo || body.chequeNo),
    transferRef: s(raw.transferRef || body.paymentReference || body.transferRef),
    paidAt:
      (raw.paidAt || body.paidAt) && isValidDateInput(raw.paidAt || body.paidAt)
        ? new Date(raw.paidAt || body.paidAt)
        : null,
    note: s(raw.note || body.paymentNote),
  };
}

function normalizeReceiptItems(items = []) {
  return normalizeItems(items).map((item) => {
    const quantity = Math.max(0, n(item?.quantity, 1));
    const unitPrice = Math.max(0, n(item?.unitPrice, 0));
    const amountInput = item?.amount;
    const amount =
      amountInput != null && amountInput !== ""
        ? Math.max(0, n(amountInput, 0))
        : Math.max(0, round2(quantity * unitPrice));

    const withholdingTaxAmount = Math.max(
      0,
      Math.min(amount, n(item?.withholdingTaxAmount, 0))
    );

    return {
      description: s(item?.description),
      quantity,
      unitPrice,
      amount,
      withholdingTaxAmount,
      netAmount: Math.max(0, amount - withholdingTaxAmount),
      note: s(item?.note),
    };
  });
}

function resolveWithholdingInputs(body = {}, normalizedItems = []) {
  const withholdingTaxEnabled = parseBoolean(
    body.withholdingTaxEnabled,
    false
  );

  let withholdingTaxInput = undefined;

  if ("withholdingTaxAmount" in body) {
    withholdingTaxInput = body.withholdingTaxAmount;
  } else if ("withholdingTax" in body) {
    withholdingTaxInput = body.withholdingTax;
  } else if (normalizedItems.length) {
    withholdingTaxInput = normalizedItems.reduce(
      (sum, item) => sum + n(item.withholdingTaxAmount, 0),
      0
    );
  }

  return {
    withholdingTaxEnabled,
    withholdingTaxInput: withholdingTaxEnabled ? withholdingTaxInput : 0,
    withholdingPercent:
      withholdingTaxEnabled && "withholdingPercent" in body
        ? body.withholdingPercent
        : undefined,
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
      withholderTaxId: s(x.clinicSnapshot?.withholderTaxId),
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
          withholdingTaxAmount: round2(n(item.withholdingTaxAmount, 0)),
          netAmount: round2(
            n(
              item.netAmount,
              Math.max(0, n(item.amount, 0) - n(item.withholdingTaxAmount, 0))
            )
          ),
          note: s(item.note),
        }))
      : [],

    subtotal: round2(n(x.subtotal, 0)),
    withholdingTaxEnabled: parseBoolean(x.withholdingTaxEnabled, false),
    withholdingTax: round2(n(x.withholdingTax, 0)),
    netAmount: round2(n(x.netAmount, 0)),
    amountInThaiText: s(x.amountInThaiText),

    paymentInfo: {
      method: s(x.paymentInfo?.method),
      bankName: s(x.paymentInfo?.bankName),
      accountName: s(x.paymentInfo?.accountName),
      accountNumber: s(x.paymentInfo?.accountNumber),
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

async function findDuplicateReceipt({
  clinicId,
  serviceMonth,
  customerName,
  excludeId = "",
}) {
  const normalizedClinicId = s(clinicId);
  const normalizedServiceMonth = s(serviceMonth);
  const normalizedCustomerName = s(customerName);

  if (!normalizedClinicId || !normalizedServiceMonth || !normalizedCustomerName) {
    return null;
  }

  const query = {
    clinicId: normalizedClinicId,
    serviceMonth: normalizedServiceMonth,
    status: { $ne: "void" },
    "customerSnapshot.customerName": {
      $regex: `^${escapeRegex(normalizedCustomerName)}$`,
      $options: "i",
    },
  };

  if (s(excludeId)) {
    query._id = { $ne: excludeId };
  }

  return SocialSecurityReceipt.findOne(query)
    .select("_id receiptNo serviceMonth customerSnapshot status")
    .lean();
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

    const clinicSnapshot = await resolveMergedClinicSnapshot({
      clinicId,
      inputSnapshot:
        req.body?.clinicSnapshot || {
          clinicName: req.body?.clinicName,
          clinicBranchName: req.body?.clinicBranchName,
          clinicAddress: req.body?.clinicAddress,
          clinicPhone: req.body?.clinicPhone,
          clinicTaxId: req.body?.clinicTaxId,
          logoUrl: req.body?.logoUrl,
          withholderTaxId: req.body?.withholderTaxId,
        },
    });

    const customerSnapshot = sanitizeCustomerSnapshot(
      req.body?.customerSnapshot || {
        customerName: req.body?.customerName,
        customerAddress: req.body?.customerAddress,
        customerTaxId: req.body?.customerTaxId,
        customerBranch: req.body?.customerBranch,
      }
    );

    const paymentInfo = sanitizePaymentInfo(req.body?.paymentInfo, req.body || {});

    if (!customerSnapshot.customerName) {
      return res.status(400).json({
        ok: false,
        code: "CUSTOMER_NAME_REQUIRED",
        message: "customerSnapshot.customerName is required",
      });
    }

    const normalizedItems = normalizeReceiptItems(req.body?.items);
    const withholdingMeta = resolveWithholdingInputs(req.body || {}, normalizedItems);

    const amountResult = calculateReceiptAmounts({
      items: normalizedItems,
      subtotal: req.body?.subtotal,
      withholdingTax: withholdingMeta.withholdingTaxInput,
      withholdingPercent: withholdingMeta.withholdingPercent,
    });

    const finalItems = amountResult.items.map((item, index) => {
      const raw = normalizedItems[index] || {};
      const amount = round2(n(item.amount, raw.amount));
      const withholdingTaxAmount = withholdingMeta.withholdingTaxEnabled
        ? round2(Math.max(0, Math.min(amount, n(raw.withholdingTaxAmount, 0))))
        : 0;

      return {
        description: s(item.description),
        quantity: round2(n(item.quantity, raw.quantity)),
        unitPrice: round2(n(item.unitPrice, raw.unitPrice)),
        amount,
        withholdingTaxAmount,
        netAmount: round2(Math.max(0, amount - withholdingTaxAmount)),
        note: s(item.note || raw.note),
      };
    });

    if (!finalItems.length) {
      return res.status(400).json({
        ok: false,
        code: "RECEIPT_ITEMS_REQUIRED",
        message: "At least one receipt item is required",
      });
    }

    const issueDate = toDateOrNow(req.body?.issueDate);
    const serviceMonth = s(req.body?.serviceMonth);

    const duplicate = await findDuplicateReceipt({
      clinicId,
      serviceMonth,
      customerName: customerSnapshot.customerName,
    });

    if (duplicate) {
      return res.status(409).json({
        ok: false,
        code: "DUPLICATE_SERVICE_MONTH_RECEIPT",
        message:
          "A social security receipt for this customer and service month already exists",
        existingReceipt: {
          id: String(duplicate._id || ""),
          receiptNo: s(duplicate.receiptNo),
          serviceMonth: s(duplicate.serviceMonth),
          status: s(duplicate.status),
          customerName: s(duplicate.customerSnapshot?.customerName),
        },
      });
    }

    const receiptNo =
      s(req.body?.receiptNo) ||
      (await nextSocialSecurityReceiptNo({ clinicId, issueDate }));

    const perItemWithholding = finalItems.reduce(
      (sum, item) => sum + n(item.withholdingTaxAmount, 0),
      0
    );

    const normalizedWithholdingTax = withholdingMeta.withholdingTaxEnabled
      ? round2(
          "withholdingTaxAmount" in (req.body || {}) ||
            "withholdingTax" in (req.body || {})
            ? amountResult.withholdingTax
            : perItemWithholding
        )
      : 0;

    const normalizedNetAmount = withholdingMeta.withholdingTaxEnabled
      ? round2(Math.max(0, amountResult.subtotal - normalizedWithholdingTax))
      : round2(amountResult.subtotal);

    const netAmountThaiText = numberToThaiText(normalizedNetAmount);

    const doc = await SocialSecurityReceipt.create({
      clinicId,
      receiptNo,
      issueDate,
      serviceMonth,
      servicePeriodText: s(req.body?.servicePeriodText),
      status: ["draft", "issued"].includes(s(req.body?.status))
        ? s(req.body?.status)
        : "issued",

      clinicSnapshot,
      customerSnapshot,
      items: finalItems,

      subtotal: amountResult.subtotal,
      withholdingTaxEnabled: withholdingMeta.withholdingTaxEnabled,
      withholdingTax: normalizedWithholdingTax,
      netAmount: normalizedNetAmount,
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

    if (doc.status === "issued") {
      return res.status(409).json({
        ok: false,
        code: "RECEIPT_ALREADY_ISSUED",
        message: "Issued receipt cannot be updated. Please void and recreate.",
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

    if (
      req.body?.clinicSnapshot ||
      "clinicName" in (req.body || {}) ||
      "clinicBranchName" in (req.body || {}) ||
      "clinicAddress" in (req.body || {}) ||
      "clinicPhone" in (req.body || {}) ||
      "clinicTaxId" in (req.body || {}) ||
      "logoUrl" in (req.body || {}) ||
      "withholderTaxId" in (req.body || {})
    ) {
      doc.clinicSnapshot = {
        ...(typeof doc.clinicSnapshot?.toObject === "function"
          ? doc.clinicSnapshot.toObject()
          : doc.clinicSnapshot || {}),
        ...sanitizeClinicSnapshot(
          req.body.clinicSnapshot || {
            clinicName: req.body?.clinicName,
            clinicBranchName: req.body?.clinicBranchName,
            clinicAddress: req.body?.clinicAddress,
            clinicPhone: req.body?.clinicPhone,
            clinicTaxId: req.body?.clinicTaxId,
            logoUrl: req.body?.logoUrl,
            withholderTaxId: req.body?.withholderTaxId,
          },
          doc.clinicId
        ),
      };
    }

    if (
      req.body?.customerSnapshot ||
      "customerName" in (req.body || {}) ||
      "customerAddress" in (req.body || {}) ||
      "customerTaxId" in (req.body || {}) ||
      "customerBranch" in (req.body || {})
    ) {
      const customerSnapshot = sanitizeCustomerSnapshot(
        req.body.customerSnapshot || {
          customerName: req.body?.customerName,
          customerAddress: req.body?.customerAddress,
          customerTaxId: req.body?.customerTaxId,
          customerBranch: req.body?.customerBranch,
        }
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

    if (
      req.body?.paymentInfo ||
      "paymentMethod" in (req.body || {}) ||
      "bankName" in (req.body || {}) ||
      "accountName" in (req.body || {}) ||
      "accountNumber" in (req.body || {}) ||
      "chequeNo" in (req.body || {}) ||
      "paymentReference" in (req.body || {}) ||
      "transferRef" in (req.body || {}) ||
      "paidAt" in (req.body || {}) ||
      "paymentNote" in (req.body || {})
    ) {
      doc.paymentInfo = {
        ...(typeof doc.paymentInfo?.toObject === "function"
          ? doc.paymentInfo.toObject()
          : doc.paymentInfo || {}),
        ...sanitizePaymentInfo(req.body.paymentInfo, req.body || {}),
      };
    }

    const hasWithholdingToggleUpdate =
      "withholdingTaxEnabled" in (req.body || {});

    const hasAmountRelatedUpdate =
      "items" in (req.body || {}) ||
      "subtotal" in (req.body || {}) ||
      "withholdingTax" in (req.body || {}) ||
      "withholdingTaxAmount" in (req.body || {}) ||
      "withholdingPercent" in (req.body || {}) ||
      hasWithholdingToggleUpdate;

    if (hasAmountRelatedUpdate) {
      const nextWithholdingEnabled = hasWithholdingToggleUpdate
        ? parseBoolean(req.body.withholdingTaxEnabled, false)
        : parseBoolean(doc.withholdingTaxEnabled, false);

      const normalizedItems =
        "items" in (req.body || {})
          ? normalizeReceiptItems(req.body.items)
          : normalizeReceiptItems(doc.items);

      const amountResult = calculateReceiptAmounts({
        items: normalizedItems,
        subtotal:
          "subtotal" in (req.body || {}) ? req.body.subtotal : doc.subtotal,
        withholdingTax: nextWithholdingEnabled
          ? ("withholdingTaxAmount" in (req.body || {})
              ? req.body.withholdingTaxAmount
              : "withholdingTax" in (req.body || {})
              ? req.body.withholdingTax
              : normalizedItems.reduce(
                  (sum, item) => sum + n(item.withholdingTaxAmount, 0),
                  0
                ))
          : 0,
        withholdingPercent:
          nextWithholdingEnabled &&
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

      const finalItems = amountResult.items.map((item, index) => {
        const raw = normalizedItems[index] || {};
        const amount = round2(n(item.amount, raw.amount));
        const withholdingTaxAmount = nextWithholdingEnabled
          ? round2(Math.max(0, Math.min(amount, n(raw.withholdingTaxAmount, 0))))
          : 0;

        return {
          description: s(item.description),
          quantity: round2(n(item.quantity, raw.quantity)),
          unitPrice: round2(n(item.unitPrice, raw.unitPrice)),
          amount,
          withholdingTaxAmount,
          netAmount: round2(Math.max(0, amount - withholdingTaxAmount)),
          note: s(item.note || raw.note),
        };
      });

      const perItemWithholding = finalItems.reduce(
        (sum, item) => sum + n(item.withholdingTaxAmount, 0),
        0
      );

      doc.items = finalItems;
      doc.subtotal = amountResult.subtotal;
      doc.withholdingTaxEnabled = nextWithholdingEnabled;
      doc.withholdingTax = nextWithholdingEnabled
        ? round2(
            "withholdingTaxAmount" in (req.body || {}) ||
              "withholdingTax" in (req.body || {})
              ? amountResult.withholdingTax
              : perItemWithholding
          )
        : 0;
      doc.netAmount = nextWithholdingEnabled
        ? round2(Math.max(0, doc.subtotal - doc.withholdingTax))
        : round2(doc.subtotal);
      doc.amountInThaiText = numberToThaiText(doc.netAmount);
    }

    const duplicate = await findDuplicateReceipt({
      clinicId: doc.clinicId,
      serviceMonth: doc.serviceMonth,
      customerName: doc.customerSnapshot?.customerName,
      excludeId: String(doc._id || ""),
    });

    if (duplicate) {
      return res.status(409).json({
        ok: false,
        code: "DUPLICATE_SERVICE_MONTH_RECEIPT",
        message:
          "A social security receipt for this customer and service month already exists",
        existingReceipt: {
          id: String(duplicate._id || ""),
          receiptNo: s(duplicate.receiptNo),
          serviceMonth: s(duplicate.serviceMonth),
          status: s(duplicate.status),
          customerName: s(duplicate.customerSnapshot?.customerName),
        },
      });
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
      code: "UPDATE_RECEIPT_FAILED",
      message: msg || "Failed to update social security receipt",
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