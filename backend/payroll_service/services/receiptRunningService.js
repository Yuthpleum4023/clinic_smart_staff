const ReceiptCounter = require("../models/ReceiptCounter");

function pad(num, size = 4) {
  const s = String(num || 0);
  return s.padStart(size, "0");
}

/**
 * format:
 * SSO-2569-04-0001
 * SSO-2569-04-0002
 *
 * ใช้ พ.ศ. 4 หลัก + เดือน + running 4 หลัก
 * และแยก counter ตาม clinic + ปี/เดือน
 */
async function nextSocialSecurityReceiptNo({ clinicId, issueDate = new Date() }) {
  const d = new Date(issueDate);

  const christianYear = d.getFullYear();
  const buddhistYear = christianYear + 543;
  const month = String(d.getMonth() + 1).padStart(2, "0");

  const safeClinicId = String(clinicId || "").trim();
  if (!safeClinicId) {
    throw new Error("clinicId is required for receipt running number");
  }

  const counterKey = `ssr:${safeClinicId}:${buddhistYear}${month}`;

  const counter = await ReceiptCounter.findOneAndUpdate(
    { key: counterKey },
    { $inc: { seq: 1 } },
    {
      new: true,
      upsert: true,
      setDefaultsOnInsert: true,
    }
  );

  const running = pad(counter.seq, 4);
  return `SSO-${buddhistYear}-${month}-${running}`;
}

module.exports = {
  nextSocialSecurityReceiptNo,
};