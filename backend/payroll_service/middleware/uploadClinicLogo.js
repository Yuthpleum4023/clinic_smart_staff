const multer = require("multer");
const path = require("path");
const fs = require("fs");

const uploadRoot = path.join(__dirname, "..", "uploads", "clinic-logos");
fs.mkdirSync(uploadRoot, { recursive: true });

function safeName(v) {
  return String(v || "")
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, "_");
}

function normalizeExt(ext) {
  const x = String(ext || "").toLowerCase().trim();
  if (x === ".jpeg") return ".jpg";
  if (x === ".jpg" || x === ".png" || x === ".webp") return x;
  return "";
}

function extFromMime(mime) {
  const m = String(mime || "").toLowerCase().trim();
  if (m === "image/png") return ".png";
  if (m === "image/jpeg" || m === "image/jpg") return ".jpg";
  if (m === "image/webp") return ".webp";
  return "";
}

function extFromOriginalName(name) {
  return normalizeExt(path.extname(String(name || "").trim()));
}

function isAllowedFile(file) {
  const mime = String(file?.mimetype || "")
    .toLowerCase()
    .trim();
  const originalname = String(file?.originalname || "").trim();
  const ext = extFromOriginalName(originalname);

  const allowedMimes = new Set([
    "image/png",
    "image/jpeg",
    "image/jpg",
    "image/webp",
    // Android / picker บางเคสส่งมาไม่ตรงแม้ไฟล์จริงถูกต้อง
    "application/octet-stream",
  ]);

  const allowedExts = new Set([".png", ".jpg", ".webp"]);

  return allowedExts.has(ext) || allowedMimes.has(mime);
}

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadRoot);
  },
  filename: function (req, file, cb) {
    const clinicId = safeName(
      req.params.clinicId || req.body?.clinicId || "clinic"
    );
    const stamp = Date.now();

    const extByName = extFromOriginalName(file?.originalname);
    const extByMime = extFromMime(file?.mimetype);
    const ext = extByName || extByMime || ".png";

    cb(null, `${clinicId}_${stamp}${ext}`);
  },
});

function fileFilter(req, file, cb) {
  console.log("[UPLOAD][CLINIC_LOGO] incoming file =", {
    fieldname: file?.fieldname,
    originalname: file?.originalname,
    mimetype: file?.mimetype,
    encoding: file?.encoding,
  });

  if (!isAllowedFile(file)) {
    return cb(new Error("Only png, jpg, jpeg, webp are allowed"));
  }

  cb(null, true);
}

const uploadClinicLogo = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
});

module.exports = uploadClinicLogo;