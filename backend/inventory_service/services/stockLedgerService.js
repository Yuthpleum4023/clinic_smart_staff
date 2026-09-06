const mongoose = require("mongoose");
const StockItem = require("../models/StockItem");
const StockMovement = require("../models/StockMovement");
const { qty } = require("../utils/quantity");
const { s } = require("../utils/strings");

function boolEnv(name, fallback = false) {
  const raw = s(process.env[name]);
  if (!raw) return fallback;
  return raw.toLowerCase() === "true";
}

function isLowStock(item, balance) {
  if (!item.lowStockAlertEnabled) return false;

  return (
    qty(balance, "balance") <=
    qty(item.minimumQty, "minimumQty")
  );
}

function optionalDate(value, label) {
  if (
    value === null ||
    value === undefined ||
    s(value) === ""
  ) {
    return null;
  }

  const d = value instanceof Date ? value : new Date(value);

  if (Number.isNaN(d.getTime())) {
    const err = new Error(`${label} must be a valid date`);
    err.status = 400;
    err.code = "INVALID_DATE";
    throw err;
  }

  return d;
}

function optionalMoney(value, label = "unitCost") {
  if (
    value === null ||
    value === undefined ||
    s(value) === ""
  ) {
    return null;
  }

  const n = Number(value);

  if (!Number.isFinite(n) || n < 0) {
    const err = new Error(
      `${label} must be a non-negative number`
    );
    err.status = 400;
    err.code = "INVALID_COST";
    throw err;
  }

  return Math.round(n * 100) / 100;
}

async function applyMovement(input, options = {}) {
  const {
    clinicId,
    stockItemId,
    type,
    quantityDelta,

    sourceType,
    sourceId = "",
    idempotencyKey = "",

    referenceType = "",
    referenceNo = "",
    lotNo = "",
    expiryDate = null,
    supplier = "",
    invoiceNo = "",

    unitCost = null,
    currency = "THB",

    performedBy,
    performedByStaffId = "",
    performedByName = "",
    actorRole = "",

    requestedBy = "",
    requestedByStaffId = "",
    requestedByName = "",

    approvedBy = "",
    approvedByName = "",
    approvedAt = null,

    reason = "",
    note = "",

    occurredAt = new Date(),
    metadata = {},
  } = input;

  const delta = qty(quantityDelta, "quantityDelta");

  if (delta === 0) {
    const err = new Error(
      "quantityDelta must not be zero"
    );
    err.status = 400;
    err.code = "ZERO_MOVEMENT";
    throw err;
  }

  if (
    !mongoose.Types.ObjectId.isValid(
      String(stockItemId || "")
    )
  ) {
    const err = new Error("Invalid stockItemId");
    err.status = 400;
    err.code = "INVALID_STOCK_ITEM_ID";
    throw err;
  }

  const normalizedOccurredAt =
    optionalDate(occurredAt, "occurredAt") || new Date();

  const normalizedExpiryDate =
    optionalDate(expiryDate, "expiryDate");

  const normalizedApprovedAt =
    optionalDate(approvedAt, "approvedAt");

  const normalizedUnitCost =
    optionalMoney(unitCost, "unitCost");

  const ownSession = !options.session;

  const session =
    options.session ||
    (await mongoose.startSession());

  let result = null;

  const work = async () => {
    if (s(idempotencyKey)) {
      const existing =
        await StockMovement.findOne({
          clinicId: s(clinicId),
          idempotencyKey: s(idempotencyKey),
        }).session(session);

      if (existing) {
        const item =
          await StockItem.findOne({
            _id: existing.stockItemId,
            clinicId: s(clinicId),
          }).session(session);

        result = {
          movement: existing,
          item,
          idempotentReplay: true,
        };

        return;
      }
    }

    const item =
      await StockItem.findOne({
        _id: stockItemId,
        clinicId: s(clinicId),
        active: true,
      }).session(session);

    if (!item) {
      const err = new Error("Stock item not found");
      err.status = 404;
      err.code = "STOCK_ITEM_NOT_FOUND";
      throw err;
    }

    const before =
      qty(item.currentQty, "currentQty");

    const after =
      qty(before + delta, "balanceAfter");

    if (
      after < 0 &&
      !boolEnv("ALLOW_NEGATIVE_STOCK", false)
    ) {
      const err = new Error("Insufficient stock");
      err.status = 409;
      err.code = "INSUFFICIENT_STOCK";
      err.details = {
        currentQty: before,
        requestedDelta: delta,
      };
      throw err;
    }

    const wasLow = !!item.lowStockActive;
    const nowLow = isLowStock(item, after);
    const now = new Date();

    // Sole materialized stock-balance write authority.
    item.currentQty = after;
    item.lowStockActive = nowLow;

    if (!wasLow && nowLow) {
      item.lowStockSince = now;
    }

    if (wasLow && !nowLow) {
      item.lowStockSince = null;
    }

    await item.save({ session });

    const [movement] =
      await StockMovement.create(
        [
          {
            clinicId: s(clinicId),
            stockItemId: item._id,

            itemSnapshot: {
              name: s(item.name),
              sku: s(item.sku),
              category: s(item.category),
              unit: s(item.unit),
            },

            type,
            quantityDelta: delta,
            balanceBefore: before,
            balanceAfter: after,

            sourceType,
            sourceId: s(sourceId),
            idempotencyKey: s(idempotencyKey),

            referenceType: s(referenceType),
            referenceNo: s(referenceNo),
            lotNo: s(lotNo),
            expiryDate: normalizedExpiryDate,
            supplier: s(supplier),
            invoiceNo: s(invoiceNo),

            unitCost: normalizedUnitCost,
            currency:
              s(currency || "THB") || "THB",

            performedBy: s(performedBy),
            performedByStaffId:
              s(performedByStaffId),
            performedByName:
              s(performedByName),
            actorRole: s(actorRole),

            requestedBy: s(requestedBy),
            requestedByStaffId:
              s(requestedByStaffId),
            requestedByName:
              s(requestedByName),

            approvedBy: s(approvedBy),
            approvedByName:
              s(approvedByName),
            approvedAt:
              normalizedApprovedAt,

            reason: s(reason),
            note: s(note),
            occurredAt:
              normalizedOccurredAt,

            metadata:
              metadata &&
              typeof metadata === "object"
                ? metadata
                : {},
          },
        ],
        { session }
      );

    result = {
      movement,
      item,
      idempotentReplay: false,
      lowStockTransition:
        !wasLow && nowLow
          ? "entered"
          : wasLow && !nowLow
            ? "cleared"
            : "none",
    };
  };

  try {
    if (ownSession) {
      await session.withTransaction(work);
    } else {
      await work();
    }

    return result;
  } catch (err) {
    if (
      err?.code === 11000 &&
      s(idempotencyKey)
    ) {
      const existing =
        await StockMovement.findOne({
          clinicId: s(clinicId),
          idempotencyKey: s(idempotencyKey),
        });

      if (existing) {
        const item =
          await StockItem.findOne({
            _id: existing.stockItemId,
            clinicId: s(clinicId),
          });

        return {
          movement: existing,
          item,
          idempotentReplay: true,
        };
      }
    }

    throw err;
  } finally {
    if (ownSession) {
      await session.endSession();
    }
  }
}

module.exports = {
  applyMovement,
  isLowStock,
};
