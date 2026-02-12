const mongoose = require("mongoose");

const ClinicSchema = new mongoose.Schema(
  {
    clinicId: { type: String, required: true, unique: true, index: true }, // CLN_xxx
    name: { type: String, required: true },
    phone: { type: String, default: "" },
    address: { type: String, default: "" },

    // owner/admin userId (reference by userId string)
    ownerUserId: { type: String, required: true, index: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model("Clinic", ClinicSchema);
