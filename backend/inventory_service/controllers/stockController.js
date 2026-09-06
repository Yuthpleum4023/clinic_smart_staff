const {
  resolveInventoryActor,
} = require("../services/actorService");

const {
  applyMovement,
} = require("../services/stockLedgerService");

const {
  positiveQty,
  qty,
} = require("../utils/quantity");

const { s } = require("../utils/strings");

function requestId(req) {
  return s(
    req.headers["idempotency-key"] ||
      req.headers["x-idempotency-key"] ||
      req.body?.idempotencyKey
  );
}

function resultPayload(result) {
  return {
    ok: true,
    idempotentReplay:
      !!result.idempotentReplay,
    lowStockTransition:
      result.lowStockTransition || "none",
    item: result.item,
    movement: result.movement,
  };
}

exports.stockIn = async (req, res, next) => {
  try {
    const actor =
      await resolveInventoryActor(req);

    const amount =
      positiveQty(
        req.body?.quantity,
        "quantity"
      );

    const result =
      await applyMovement({
        clinicId: actor.clinicId,
        stockItemId:
          req.body?.stockItemId,

        type: "stock_in",
        quantityDelta: amount,

        sourceType: "app",
        sourceId: s(req.body?.sourceId),
        idempotencyKey: requestId(req),

        referenceType:
          s(
            req.body?.referenceType ||
              "stock_in"
          ),

        referenceNo:
          s(
            req.body?.referenceNo ||
              req.body?.invoiceNo
          ),

        lotNo: s(req.body?.lotNo),
        expiryDate:
          req.body?.expiryDate || null,
        supplier:
          s(req.body?.supplier),
        invoiceNo:
          s(req.body?.invoiceNo),

        unitCost:
          actor.hasAdmin
            ? req.body?.unitCost
            : null,

        currency:
          actor.hasAdmin
            ? s(
                req.body?.currency ||
                  "THB"
              )
            : "THB",

        performedBy: actor.userId,
        performedByStaffId:
          actor.staffId,
        performedByName:
          actor.displayName,
        actorRole: actor.role,

        reason:
          s(
            req.body?.reason ||
              "stock in"
          ),

        note: s(req.body?.note),

        occurredAt:
          req.body?.occurredAt ||
          new Date(),

        metadata: {},
      });

    return res
      .status(
        result.idempotentReplay
          ? 200
          : 201
      )
      .json(resultPayload(result));
  } catch (err) {
    return next(err);
  }
};

exports.consume = async (req, res, next) => {
  try {
    const actor =
      await resolveInventoryActor(req);

    const amount =
      positiveQty(
        req.body?.quantity,
        "quantity"
      );

    const reason =
      s(req.body?.reason);

    if (!reason) {
      const err =
        new Error(
          "reason is required for manual consumption"
        );

      err.status = 400;
      err.code = "REASON_REQUIRED";
      throw err;
    }

    const result =
      await applyMovement({
        clinicId: actor.clinicId,
        stockItemId:
          req.body?.stockItemId,

        type: "manual_consumption",
        quantityDelta: -amount,

        sourceType: "app",
        sourceId: s(req.body?.sourceId),
        idempotencyKey: requestId(req),

        referenceType:
          s(
            req.body?.referenceType ||
              "manual_usage"
          ),

        referenceNo:
          s(req.body?.referenceNo),

        lotNo: s(req.body?.lotNo),

        performedBy: actor.userId,
        performedByStaffId:
          actor.staffId,
        performedByName:
          actor.displayName,
        actorRole: actor.role,

        reason,
        note: s(req.body?.note),

        occurredAt:
          req.body?.occurredAt ||
          new Date(),

        metadata: {},
      });

    return res
      .status(
        result.idempotentReplay
          ? 200
          : 201
      )
      .json(resultPayload(result));
  } catch (err) {
    return next(err);
  }
};

exports.adminAdjust =
  async (req, res, next) => {
    try {
      const actor =
        await resolveInventoryActor(req);

      if (!actor.hasAdmin) {
        const err =
          new Error("Admin only");

        err.status = 403;
        err.code = "ADMIN_ONLY";
        throw err;
      }

      const delta =
        qty(
          req.body?.quantityDelta,
          "quantityDelta"
        );

      if (delta === 0) {
        const err =
          new Error(
            "quantityDelta must not be zero"
          );

        err.status = 400;
        err.code = "ZERO_MOVEMENT";
        throw err;
      }

      const reason =
        s(req.body?.reason);

      if (!reason) {
        const err =
          new Error(
            "reason is required"
          );

        err.status = 400;
        err.code = "REASON_REQUIRED";
        throw err;
      }

      const result =
        await applyMovement({
          clinicId: actor.clinicId,
          stockItemId:
            req.body?.stockItemId,

          type: "adjustment",
          quantityDelta: delta,

          sourceType: "app",
          sourceId:
            s(req.body?.sourceId),

          idempotencyKey:
            requestId(req),

          referenceType:
            s(
              req.body?.referenceType ||
                "admin_adjustment"
            ),

          referenceNo:
            s(req.body?.referenceNo),

          performedBy: actor.userId,
          performedByStaffId:
            actor.staffId,
          performedByName:
            actor.displayName,
          actorRole: actor.role,

          approvedBy: actor.userId,
          approvedByName:
            actor.displayName,
          approvedAt: new Date(),

          reason,
          note: s(req.body?.note),

          metadata: {},
        });

      return res
        .status(
          result.idempotentReplay
            ? 200
            : 201
        )
        .json(resultPayload(result));
    } catch (err) {
      return next(err);
    }
  };
