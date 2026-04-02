const router = require("express").Router();

const { auth, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/socialSecurityReceiptController");

function notImplemented(name) {
  return (req, res) => {
    return res.status(501).json({
      ok: false,
      code: "NOT_IMPLEMENTED",
      message: `${name} is not implemented`,
    });
  };
}

function useHandler(handler, name) {
  return typeof handler === "function" ? handler : notImplemented(name);
}

/**
 * roles:
 * - admin / clinic_admin = เหมาะสุดสำหรับออกเอกสารการเงิน
 * - เผื่อ legacy role "clinic" ไว้แบบ no-break
 */
const RECEIPT_WRITE_ROLES = ["admin", "clinic_admin", "clinic"];
const RECEIPT_READ_ROLES = ["admin", "clinic_admin", "clinic"];

// create
router.post(
  "/",
  auth,
  requireRole(RECEIPT_WRITE_ROLES),
  useHandler(ctrl.createReceipt, "createReceipt")
);

// list
router.get(
  "/",
  auth,
  requireRole(RECEIPT_READ_ROLES),
  useHandler(ctrl.listReceipts, "listReceipts")
);

// detail
router.get(
  "/:id",
  auth,
  requireRole(RECEIPT_READ_ROLES),
  useHandler(ctrl.getReceiptById, "getReceiptById")
);

// update
router.put(
  "/:id",
  auth,
  requireRole(RECEIPT_WRITE_ROLES),
  useHandler(ctrl.updateReceipt, "updateReceipt")
);

// void
router.post(
  "/:id/void",
  auth,
  requireRole(RECEIPT_WRITE_ROLES),
  useHandler(ctrl.voidReceipt, "voidReceipt")
);

// generate pdf
router.post(
  "/:id/generate-pdf",
  auth,
  requireRole(RECEIPT_WRITE_ROLES),
  useHandler(ctrl.generateReceiptPdf, "generateReceiptPdf")
);

// pdf info
router.get(
  "/:id/pdf",
  auth,
  requireRole(RECEIPT_READ_ROLES),
  useHandler(ctrl.getReceiptPdfInfo, "getReceiptPdfInfo")
);

// stream/open pdf
router.get(
  "/:id/pdf/open",
  auth,
  requireRole(RECEIPT_READ_ROLES),
  useHandler(ctrl.streamReceiptPdf, "streamReceiptPdf")
);

module.exports = router;