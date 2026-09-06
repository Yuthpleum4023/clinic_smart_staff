const InventoryItemCounter = require("../models/InventoryItemCounter");
const { s } = require("../utils/strings");

const ITEM_NAMESPACE = "stock_item";
const ITEM_PREFIX = "INV";
const ITEM_NUMBER_WIDTH = 6;

function formatItemCode(sequenceValue) {
  const n = Number(sequenceValue);

  if (!Number.isSafeInteger(n) || n <= 0) {
    const err = new Error("Invalid inventory item sequence");
    err.status = 500;
    err.code = "INVALID_ITEM_SEQUENCE";
    throw err;
  }

  return `${ITEM_PREFIX}-${String(n).padStart(ITEM_NUMBER_WIDTH, "0")}`;
}

async function incrementCounter({ clinicId }) {
  return InventoryItemCounter.findOneAndUpdate(
    {
      clinicId,
      namespace: ITEM_NAMESPACE,
    },
    {
      $inc: { value: 1 },
      $setOnInsert: {
        clinicId,
        namespace: ITEM_NAMESPACE,
      },
    },
    {
      new: true,
      upsert: true,
      runValidators: true,
      setDefaultsOnInsert: true,
    }
  );
}

async function allocateInventoryItemCode({ clinicId }) {
  const scopedClinicId = s(clinicId);

  if (!scopedClinicId) {
    const err = new Error("Missing clinicId for item-code allocation");
    err.status = 500;
    err.code = "ITEM_CODE_SCOPE_REQUIRED";
    throw err;
  }

  let counter;

  try {
    counter = await incrementCounter({ clinicId: scopedClinicId });
  } catch (err) {
    if (err?.code !== 11000) throw err;
    counter = await incrementCounter({ clinicId: scopedClinicId });
  }

  return formatItemCode(counter.value);
}

module.exports = {
  allocateInventoryItemCode,
  formatItemCode,
};
