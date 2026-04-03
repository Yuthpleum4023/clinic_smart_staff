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

function extFromMime(mime) {
  const m = String(mime || "").toLowerCase();
  if (m === "image/png") return ".png";
  if (m === "image/jpeg" || m === "image/jpg") return ".jpg";
  if (m === "image/webp") return ".webp";
  return ".png";
}

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadRoot);
  },
  filename: function (req, file, cb) {
    const ext = extFromMime(file.mimetype);
    const clinicId = safeName(
      req.params.clinicId || req.body?.clinicId || "clinic"
    );
    const stamp = Date.now();
    cb(null, `${clinicId}_${stamp}${ext}`);
  },
});

function fileFilter(req, file, cb) {
  const allowed = ["image/png", "image/jpeg", "image/jpg", "image/webp"];
  if (!allowed.includes(String(file.mimetype || "").toLowerCase())) {
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