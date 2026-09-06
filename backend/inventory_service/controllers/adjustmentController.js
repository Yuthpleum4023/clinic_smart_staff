const mongoose = require("mongoose");
const StockItem = require("../models/StockItem");

const StockAdjustmentRequest =
  require("../models/StockAdjustmentRequest");

const {
  resolveInventoryActor,
} = require("../services/actorService");

const {
  applyMovement,
} = require("../services/stockLedgerService");

const { qty } = require("../utils/quantity");
const { s } = require("../utils/strings");

function objectId(v, label) {
  if (
    !mongoose.Types.ObjectId.isValid(
      String(v || "")
    )
  ) {
    const err =
      new Error(`Invalid ${label}`);

    err.status = 400;
    err.code = "INVALID_ID";
    throw err;
  }

  return v;
}

exports.createRequest =
  async (req, res, next) => {
    try {
      const actor =
        await resolveInventoryActor(req, {
          verifyEmployee: true,
        });

      if (actor.role !== "employee") {
        const err =
          new Error(
            "Staff adjustment request is for employee corrections"
          );

        err.status = 403;
        err.code =
          "STAFF_ADJUSTMENT_ONLY";

        throw err;
      }

      const stockItemId =
        objectId(
          req.body?.stockItemId,
          "stockItemId"
        );

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

      const observedQty =
        qty(
          req.body?.observedQty,
          "observedQty"
        );

      if (observedQty < 0) {
        const err =
          new Error(
            "observedQty must be >= 0"
          );

        err.status = 400;
        err.code =
          "INVALID_OBSERVED_QTY";

        throw err;
      }

      const item =
        await StockItem.findOne({
          _id: stockItemId,
          clinicId: actor.clinicId,
          active: true,
        });

      if (!item) {
        const err =
          new Error(
            "Stock item not found"
          );

        err.status = 404;
        err.code =
          "STOCK_ITEM_NOT_FOUND";

        throw err;
      }

      const snapshotQty =
        qty(
          item.currentQty,
          "currentQty"
        );

      const requestedDelta =
        qty(
          observedQty - snapshotQty,
          "requestedDelta"
        );

      if (requestedDelta === 0) {
        const err =
          new Error(
            "No stock correction is required"
          );

        err.status = 400;
        err.code =
          "NO_ADJUSTMENT_REQUIRED";

        throw err;
      }

      const request =
        await StockAdjustmentRequest.create({
          clinicId: actor.clinicId,
          stockItemId: item._id,

          snapshotQty,
          observedQty,
          requestedDelta,

          reason,

          requestedBy: actor.userId,
          requestedByStaffId:
            actor.staffId,
          requestedByName:
            actor.displayName,
        });

      return res
        .status(201)
        .json({
          ok: true,
          request,
        });
    } catch (err) {
      return next(err);
    }
  };

exports.listPending =
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

      const requests =
        await StockAdjustmentRequest.find({
          clinicId: actor.clinicId,
          status: "pending",
        })
          .populate(
            "stockItemId",
            "name sku unit currentQty minimumQty"
          )
          .sort({ createdAt: 1 })
          .lean();

      return res.json({
        ok: true,
        requests,
      });
    } catch (err) {
      return next(err);
    }
  };

exports.approve =
  async (req, res, next) => {
    const session =
      await mongoose.startSession();

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

      objectId(
        req.params.id,
        "adjustment request id"
      );

      let output = null;

      await session.withTransaction(
        async () => {
          const request =
            await StockAdjustmentRequest.findOne({
              _id: req.params.id,
              clinicId: actor.clinicId,
              status: "pending",
            }).session(session);

          if (!request) {
            const existing =
              await StockAdjustmentRequest.findOne({
                _id: req.params.id,
                clinicId:
                  actor.clinicId,
              }).session(session);

            if (!existing) {
              const err =
                new Error(
                  "Adjustment request not found"
                );

              err.status = 404;
              err.code =
                "ADJUSTMENT_NOT_FOUND";

              throw err;
            }

            const err =
              new Error(
                `Adjustment request is already ${existing.status}`
              );

            err.status = 409;
            err.code =
              "ADJUSTMENT_ALREADY_REVIEWED";

            throw err;
          }

          const result =
            await applyMovement(
              {
                clinicId:
                  actor.clinicId,

                stockItemId:
                  request.stockItemId,

                type: "adjustment",
                quantityDelta:
                  request.requestedDelta,

                sourceType:
                  "adjustment_request",

                sourceId:
                  String(request._id),

                idempotencyKey:
                  `adjustment:${request._id}`,

                referenceType:
                  "adjustment_request",

                referenceNo:
                  String(request._id),

                performedBy:
                  actor.userId,

                performedByStaffId:
                  actor.staffId,

                performedByName:
                  actor.displayName,

                actorRole:
                  actor.role,

                requestedBy:
                  request.requestedBy,

                requestedByStaffId:
                  request.requestedByStaffId,

                requestedByName:
                  request.requestedByName,

                approvedBy:
                  actor.userId,

                approvedByName:
                  actor.displayName,

                approvedAt:
                  new Date(),

                reason:
                  request.reason,

                note:
                  s(
                    req.body
                      ?.resolutionNote
                  ),

                metadata: {
                  adjustmentRequestId:
                    String(request._id),

                  snapshotQty:
                    request.snapshotQty,

                  observedQty:
                    request.observedQty,
                },
              },
              { session }
            );

          request.status = "approved";

          request.reviewedBy =
            actor.userId;

          request.reviewedByName =
            actor.displayName;

          request.reviewedAt =
            new Date();

          request.resolutionNote =
            s(
              req.body?.resolutionNote
            );

          request.movementId =
            result.movement._id;

          await request.save({
            session,
          });

          output = {
            request,
            ...result,
          };
        }
      );

      return res.json({
        ok: true,
        ...output,
      });
    } catch (err) {
      return next(err);
    } finally {
      await session.endSession();
    }
  };

exports.reject =
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

      objectId(
        req.params.id,
        "adjustment request id"
      );

      const request =
        await StockAdjustmentRequest.findOneAndUpdate(
          {
            _id: req.params.id,
            clinicId: actor.clinicId,
            status: "pending",
          },
          {
            $set: {
              status: "rejected",

              reviewedBy:
                actor.userId,

              reviewedByName:
                actor.displayName,

              reviewedAt:
                new Date(),

              resolutionNote:
                s(
                  req.body
                    ?.resolutionNote
                ),
            },
          },
          { new: true }
        );

      if (!request) {
        const existing =
          await StockAdjustmentRequest.findOne({
            _id: req.params.id,
            clinicId:
              actor.clinicId,
          });

        const err =
          new Error(
            existing
              ? `Adjustment request is already ${existing.status}`
              : "Adjustment request not found"
          );

        err.status =
          existing ? 409 : 404;

        err.code =
          existing
            ? "ADJUSTMENT_ALREADY_REVIEWED"
            : "ADJUSTMENT_NOT_FOUND";

        throw err;
      }

      return res.json({
        ok: true,
        request,
      });
    } catch (err) {
      return next(err);
    }
  };
