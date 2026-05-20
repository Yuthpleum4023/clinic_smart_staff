const mongoose = require("mongoose");

const ClinicSecuritySettingSchema = new mongoose.Schema(
  {
    clinicId: {
      type: String,
      required: true,
      unique: true,
      trim: true,
    },

    pinHash: {
      type: String,
      default: "",
      select: false,
    },

    pinUpdatedAt: {
      type: Date,
      default: null,
    },

    updatedBy: {
      type: String,
      default: "",
      trim: true,
    },
  },
  {
    timestamps: true,
    collection: "clinic_security_settings",
  }
);

module.exports =
  mongoose.models.ClinicSecuritySetting ||
  mongoose.model("ClinicSecuritySetting", ClinicSecuritySettingSchema);
