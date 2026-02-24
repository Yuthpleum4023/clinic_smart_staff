const Clinic = require("../models/Clinic");

exports.updateClinicBrand = async (req, res) => {
  try {
    const { clinicId, brandAbbr, brandColor } = req.body;

    if (!clinicId) {
      return res.status(400).json({
        ok: false,
        message: "clinicId required",
      });
    }

    const clinic = await Clinic.findOne({ clinicId });

    if (!clinic) {
      return res.status(404).json({
        ok: false,
        message: "clinic not found",
      });
    }

    clinic.brandAbbr = (brandAbbr || "").toString().trim();
    clinic.brandColor = (brandColor || "").toString().trim();

    await clinic.save();

    res.json({
      ok: true,
      clinic,
    });
  } catch (e) {
    res.status(500).json({
      ok: false,
      message: e.message,
    });
  }
};