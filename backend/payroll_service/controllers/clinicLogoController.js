const fs = require("fs");
const path = require("path");
const Clinic = require("../models/Clinic");

function s(v) {
  return String(v || "").trim();
}

function buildBaseUrl(req) {
  const proto = s(req.headers["x-forwarded-proto"]) || req.protocol || "https";
  const host = s(req.headers["x-forwarded-host"]) || s(req.get("host"));
  return `${proto}://${host}`;
}

function toAbsPath(p) {
  const x = s(p);
  if (!x) return "";
  if (path.isAbsolute(x)) return x;
  return path.join(process.cwd(), x);
}

function safeUnlink(filePath) {
  try {
    const abs = toAbsPath(filePath);
    if (!abs) return false;
    if (!fs.existsSync(abs)) return false;
    fs.unlinkSync(abs);
    return true;
  } catch (_) {
    return false;
  }
}

function normalizeStoredLogoPath(filePath) {
  const raw = s(filePath).replace(/\\/g, "/");
  if (!raw) return "";

  const marker = "uploads/clinic-logos/";
  const idx = raw.lastIndexOf(marker);
  if (idx >= 0) {
    return raw.slice(idx);
  }

  return raw;
}

exports.uploadClinicLogo = async (req, res) => {
  try {
    const clinicId = s(req.params.clinicId || req.body?.clinicId);
    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        code: "CLINIC_ID_REQUIRED",
        message: "clinicId is required",
      });
    }

    if (!req.file) {
      return res.status(400).json({
        ok: false,
        code: "LOGO_FILE_REQUIRED",
        message: "Logo file is required",
      });
    }

    // ✅ IMPORTANT:
    // model นี้ใช้ clinicId เป็นหลัก ไม่ใช่ _id
    const clinic = await Clinic.findOne({ clinicId });
    if (!clinic) {
      safeUnlink(req.file.path);

      return res.status(404).json({
        ok: false,
        code: "CLINIC_NOT_FOUND",
        message: "Clinic not found",
      });
    }

    const oldLogoPath = s(clinic.logoPath);

    const publicFileName = s(req.file.filename);
    const publicUrl = `${buildBaseUrl(req)}/clinic-logo-files/${encodeURIComponent(
      publicFileName
    )}`;

    clinic.logoUrl = publicUrl;
    clinic.logoPath = normalizeStoredLogoPath(req.file.path);
    clinic.logoUpdatedAt = new Date();

    await clinic.save();

    // ลบไฟล์เก่า หลัง save ใหม่สำเร็จแล้ว
    if (oldLogoPath && oldLogoPath !== clinic.logoPath) {
      safeUnlink(oldLogoPath);
    }

    return res.status(200).json({
      ok: true,
      message: "Clinic logo uploaded successfully",
      clinic: {
        _id: String(clinic._id || ""),
        clinicId: s(clinic.clinicId),
        name: s(clinic.name),
        logoUrl: s(clinic.logoUrl),
        logoPath: s(clinic.logoPath),
        logoUpdatedAt: clinic.logoUpdatedAt,
      },
    });
  } catch (err) {
    console.error("[clinicLogoController.uploadClinicLogo] error:", err);

    if (req.file?.path) {
      safeUnlink(req.file.path);
    }

    return res.status(500).json({
      ok: false,
      code: "UPLOAD_CLINIC_LOGO_FAILED",
      message: "Failed to upload clinic logo",
    });
  }
};

exports.removeClinicLogo = async (req, res) => {
  try {
    const clinicId = s(req.params.clinicId || req.body?.clinicId);
    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        code: "CLINIC_ID_REQUIRED",
        message: "clinicId is required",
      });
    }

    // ✅ IMPORTANT:
    // model นี้ใช้ clinicId เป็นหลัก ไม่ใช่ _id
    const clinic = await Clinic.findOne({ clinicId });
    if (!clinic) {
      return res.status(404).json({
        ok: false,
        code: "CLINIC_NOT_FOUND",
        message: "Clinic not found",
      });
    }

    const oldLogoPath = s(clinic.logoPath);

    clinic.logoUrl = "";
    clinic.logoPath = "";
    clinic.logoUpdatedAt = new Date();

    await clinic.save();

    if (oldLogoPath) {
      safeUnlink(oldLogoPath);
    }

    return res.status(200).json({
      ok: true,
      message: "Clinic logo removed successfully",
      clinic: {
        _id: String(clinic._id || ""),
        clinicId: s(clinic.clinicId),
        name: s(clinic.name),
        logoUrl: "",
        logoPath: "",
        logoUpdatedAt: clinic.logoUpdatedAt,
      },
    });
  } catch (err) {
    console.error("[clinicLogoController.removeClinicLogo] error:", err);

    return res.status(500).json({
      ok: false,
      code: "REMOVE_CLINIC_LOGO_FAILED",
      message: "Failed to remove clinic logo",
    });
  }
};