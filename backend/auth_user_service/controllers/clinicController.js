const Clinic = require("../models/Clinic");

async function getMyClinic(req, res) {
  const { clinicId } = req.user || {};
  const clinic = await Clinic.findOne({ clinicId }).lean();
  if (!clinic) return res.status(404).json({ message: "Clinic not found" });
  return res.json({ clinic });
}

module.exports = { getMyClinic };
